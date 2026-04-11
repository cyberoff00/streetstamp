#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

cd "$ROOT"

echo "Project root: $ROOT"

[[ -f "StreetStamps.xcodeproj/project.pbxproj" ]] || fail "missing Xcode project file"
pass "xcode project exists"

[[ -f "StreetStamps/BackendConfig.swift" ]] || fail "missing BackendConfig.swift"
[[ -f "StreetStamps/FriendsHubView.swift" ]] || fail "missing FriendsHubView.swift"
pass "core app files exist"

[[ -f "backend-node-v1/server.js" ]] || fail "missing backend-node-v1/server.js"
node --check backend-node-v1/server.js >/dev/null
pass "backend-node-v1/server.js syntax ok"

[[ -f "backend-node-v1/.env.production.example" ]] || fail "missing backend-node-v1/.env.production.example"
pass "production env example exists"

if [[ -f "GoogleService-Info.plist" ]]; then
  pass "GoogleService-Info.plist exists"
else
  warn "GoogleService-Info.plist missing (Google login may fail)"
fi

if rg -n 'JWT_SECRET:\s*"\$\{JWT_SECRET:-change-me\}"' backend-node-v1/docker-compose.yml >/dev/null 2>&1; then
  warn "docker-compose.yml still has a development JWT fallback; production must override JWT_SECRET"
else
  pass "docker-compose.yml does not expose dev JWT fallback"
fi

if rg -n 'CORS_ALLOWED_ORIGINS' backend-node-v1/docker-compose.yml >/dev/null 2>&1; then
  pass "docker-compose.yml exposes configurable CORS allowlist"
else
  warn "docker-compose.yml missing CORS_ALLOWED_ORIGINS"
fi

if rg -n 'MEDIA_UPLOAD_MAX_BYTES|JSON_BODY_LIMIT_MB|AUTH_RATE_LIMIT_MAX' backend-node-v1/docker-compose.yml >/dev/null 2>&1; then
  pass "docker-compose.yml exposes request hardening knobs"
else
  warn "docker-compose.yml missing request hardening knobs"
fi

[[ -f "docs/ops/nginx-streetstamps.conf" ]] || warn "missing Nginx production template"
[[ -f "scripts/readonly_prod_check.sh" ]] || warn "missing read-only production check script"

if rg -n "GoogleSignIn" StreetStamps.xcodeproj/project.pbxproj >/dev/null 2>&1; then
  pass "GoogleSignIn linkage found in project"
else
  warn "GoogleSignIn linkage not detected in project.pbxproj"
fi

if rg -n "profileVisibility|handle|stats|inviteCode" backend-node-v1/server.js >/dev/null 2>&1; then
  pass "backend exposes social profile fields"
else
  warn "backend may not expose complete social profile fields"
fi

if rg -n "MigrationStatusStore|JourneyMigrationReport|pendingMigrationFromGuestUserID" StreetStamps >/dev/null 2>&1; then
  pass "migration persistence hooks present"
else
  warn "migration persistence hooks not fully present"
fi

echo "PREFLIGHT_DONE"
