#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_HOST="${SERVER_HOST:-root@101.132.159.73}"
REMOTE_DIR="${REMOTE_DIR:-/opt/streetstamps/backend-node-v1}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/streetstamps/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REMOTE_RELEASE_DIR="${BACKUP_ROOT}/release/${TIMESTAMP}"
REMOTE_DB_BACKUP="${BACKUP_ROOT}/db/${TIMESTAMP}.sql"
EXPECTED_AUTH_MODE="${EXPECTED_AUTH_MODE:-backend_jwt_only}"
EXPECTED_WRITE_FROZEN="${EXPECTED_WRITE_FROZEN:-false}"
LOCAL_GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
LOCAL_GIT_TREE_STATE="clean"
LOCAL_GIT_STATUS_LINES="0"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

cd "$ROOT_DIR"

if [[ -n "$(git status --short 2>/dev/null || true)" ]]; then
  LOCAL_GIT_TREE_STATE="dirty"
  LOCAL_GIT_STATUS_LINES="$(git status --short 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${ALLOW_DIRTY:-0}" != "1" ]]; then
    fail "working tree is dirty (${LOCAL_GIT_STATUS_LINES} changed files). Commit first or set ALLOW_DIRTY=1 to override."
  fi
  echo "[WARN] deploying from dirty worktree (${LOCAL_GIT_STATUS_LINES} changed files)"
fi

[[ -f "backend-node-v1/server.js" ]] || fail "missing backend-node-v1/server.js"
[[ -f "backend-node-v1/docker-compose.yml" ]] || fail "missing backend-node-v1/docker-compose.yml"
[[ -f "backend-node-v1/package.json" ]] || fail "missing backend-node-v1/package.json"
[[ -f "backend-node-v1/package-lock.json" ]] || fail "missing backend-node-v1/package-lock.json"
[[ -f "backend-node-v1/Dockerfile" ]] || fail "missing backend-node-v1/Dockerfile"
[[ -f "backend-node-v1/DEPLOY.md" ]] || fail "missing backend-node-v1/DEPLOY.md"
[[ -f "backend-node-v1/db-relational.js" ]] || fail "missing backend-node-v1/db-relational.js"
[[ -f "backend-node-v1/postcard-rules.js" ]] || fail "missing backend-node-v1/postcard-rules.js"
[[ -f "backend-node-v1/apns.js" ]] || fail "missing backend-node-v1/apns.js"
[[ -f "docs/ops/PRODUCTION_WORKFLOW.md" ]] || fail "missing docs/ops/PRODUCTION_WORKFLOW.md"
[[ -f "docs/ops/SERVER_BOOTSTRAP.md" ]] || fail "missing docs/ops/SERVER_BOOTSTRAP.md"
[[ -f "scripts/check_auth_mode.sh" ]] || fail "missing scripts/check_auth_mode.sh"
[[ -f "scripts/readonly_prod_check.sh" ]] || fail "missing scripts/readonly_prod_check.sh"

bash scripts/preflight_check.sh >/dev/null
pass "local preflight passed"

node --check backend-node-v1/server.js >/dev/null
pass "backend syntax check passed"

echo "[INFO] creating remote backups under ${BACKUP_ROOT}"
ssh -o StrictHostKeyChecking=no "$SERVER_HOST" "\
  set -euo pipefail; \
  mkdir -p '${BACKUP_ROOT}/db' '${BACKUP_ROOT}/release'; \
  docker exec streetstamps-postgres pg_dump -U streetstamps streetstamps > '${REMOTE_DB_BACKUP}'; \
  mkdir -p '${REMOTE_RELEASE_DIR}'; \
  cd '${REMOTE_DIR}'; \
  cp server.js docker-compose.yml package.json package-lock.json Dockerfile .env '${REMOTE_RELEASE_DIR}/'; \
  if [ -f db-relational.js ]; then cp db-relational.js '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f postcard-rules.js ]; then cp postcard-rules.js '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f apns.js ]; then cp apns.js '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f .deployed-git-commit ]; then cp .deployed-git-commit '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f entrypoint.sh ]; then cp entrypoint.sh '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f DEPLOY.md ]; then cp DEPLOY.md '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f check_auth_mode.sh ]; then cp check_auth_mode.sh '${REMOTE_RELEASE_DIR}/'; fi; \
  if [ -f readonly_prod_check.sh ]; then cp readonly_prod_check.sh '${REMOTE_RELEASE_DIR}/'; fi; \
  mkdir -p '${REMOTE_RELEASE_DIR}/docs/ops'; \
  if [ -f docs/ops/PRODUCTION_WORKFLOW.md ]; then cp docs/ops/PRODUCTION_WORKFLOW.md '${REMOTE_RELEASE_DIR}/docs/ops/'; fi; \
  if [ -f docs/ops/SERVER_BOOTSTRAP.md ]; then cp docs/ops/SERVER_BOOTSTRAP.md '${REMOTE_RELEASE_DIR}/docs/ops/'; fi; \
  printf '%s\n%s\n' '${REMOTE_DB_BACKUP}' '${REMOTE_RELEASE_DIR}'"

pass "remote backup created"

scp -o StrictHostKeyChecking=no \
  backend-node-v1/server.js \
  backend-node-v1/db-relational.js \
  backend-node-v1/postcard-rules.js \
  backend-node-v1/apns.js \
  backend-node-v1/docker-compose.yml \
  backend-node-v1/package.json \
  backend-node-v1/package-lock.json \
  backend-node-v1/Dockerfile \
  backend-node-v1/entrypoint.sh \
  backend-node-v1/DEPLOY.md \
  scripts/check_auth_mode.sh \
  scripts/readonly_prod_check.sh \
  "$SERVER_HOST:$REMOTE_DIR/"

ssh -o StrictHostKeyChecking=no "$SERVER_HOST" "mkdir -p '$REMOTE_DIR/migrations'"

scp -o StrictHostKeyChecking=no \
  backend-node-v1/migrations/001-create-tables.sql \
  backend-node-v1/migrations/002-migrate-data.js \
  "$SERVER_HOST:$REMOTE_DIR/migrations/"

ssh -o StrictHostKeyChecking=no "$SERVER_HOST" "mkdir -p '$REMOTE_DIR/docs/ops'"

scp -o StrictHostKeyChecking=no \
  docs/ops/PRODUCTION_WORKFLOW.md \
  docs/ops/SERVER_BOOTSTRAP.md \
  "$SERVER_HOST:$REMOTE_DIR/docs/ops/"

pass "deployment artifacts uploaded"

ssh -o StrictHostKeyChecking=no "$SERVER_HOST" "\
  set -euo pipefail; \
  cd '${REMOTE_DIR}'; \
  chmod +x check_auth_mode.sh readonly_prod_check.sh; \
  grep -q '^WRITE_FREEZE_ENABLED=' .env || echo 'WRITE_FREEZE_ENABLED=false' >> .env; \
  chown -R 1000:1000 media data 2>/dev/null || true; \
  docker compose up -d --build api; \
  sleep 8; \
  curl -fsS http://127.0.0.1:18080/v1/health >/dev/null; \
  BASE_URL=http://127.0.0.1:18080 \
  EXPECTED_AUTH_MODE='${EXPECTED_AUTH_MODE}' \
  EXPECTED_WRITE_FROZEN='${EXPECTED_WRITE_FROZEN}' \
  bash ./readonly_prod_check.sh; \
  printf 'commit=%s\ntree_state=%s\nstatus_lines=%s\ndeployed_at_utc=%s\nremote_dir=%s\n' \
    '${LOCAL_GIT_COMMIT}' \
    '${LOCAL_GIT_TREE_STATE}' \
    '${LOCAL_GIT_STATUS_LINES}' \
    \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \
    '${REMOTE_DIR}' > .deployed-git-commit"

pass "remote deploy checks passed"
echo "DB_BACKUP=${REMOTE_DB_BACKUP}"
echo "RELEASE_BACKUP=${REMOTE_RELEASE_DIR}"
