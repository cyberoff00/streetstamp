# Production Git-Controlled Backend Deploy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the production backend deployment on `101.132.159.73` from hand-maintained files to a git-controlled workflow without breaking the running API or its persisted data.

**Architecture:** Keep the existing production data and media mounts under `/opt/streetstamps/backend-node-v1`, but introduce a separate git working tree on the server that becomes the only source for deployable backend code. Add a small deploy script that syncs tracked backend files from the git checkout into the production directory, preserves `.env`, `data`, and `media`, rebuilds the `api` container, and records the deployed commit.

**Tech Stack:** Git, Docker Compose, Node.js backend, Bash deploy script, production SSH host `101.132.159.73`

---

### Task 1: Add a production deploy script to the repo

**Files:**
- Create: `scripts/deploy_backend_from_git.sh`
- Test: Run script help and shell syntax checks locally

**Step 1: Write the failing script contract**

Document the intended behavior in the script header:
- require a git checkout path
- require a production target path
- sync only tracked backend files
- preserve `.env`, `data`, `media`, and local backups
- run `docker compose up -d --build api`
- write the deployed commit to a marker file

**Step 2: Run shell syntax verification**

Run: `bash -n scripts/deploy_backend_from_git.sh`
Expected: the file does not exist yet or syntax check fails before implementation

**Step 3: Write minimal implementation**

Implement a bash script that:
- accepts `REPO_DIR` and `TARGET_DIR`
- verifies both directories exist
- syncs `backend-node-v1/` from the repo into the target with `rsync`
- excludes `.env`, `data`, `media`, `backups`, and backup files
- runs `docker compose up -d --build api` in the target
- writes `git -C "$REPO_DIR" rev-parse HEAD` to `.deployed-git-commit`

**Step 4: Run shell syntax verification again**

Run: `bash -n scripts/deploy_backend_from_git.sh`
Expected: PASS with no output

**Step 5: Commit**

```bash
git add scripts/deploy_backend_from_git.sh
git commit -m "ops: add git-controlled backend deploy script"
```

### Task 2: Add deployed version visibility

**Files:**
- Modify: `backend-node-v1/server.js`
- Test: `backend-node-v1/tests/security-hardening.test.mjs` if applicable, otherwise targeted health verification

**Step 1: Write the failing test**

Add or extend a lightweight verification to assert the health or version output exposes a deployed commit marker when present.

**Step 2: Run test to verify it fails**

Run: `node --test backend-node-v1/tests/security-hardening.test.mjs`
Expected: FAIL because deployed commit metadata is not yet surfaced

**Step 3: Write minimal implementation**

Update `backend-node-v1/server.js` so `/v1/health` includes a field sourced from `.deployed-git-commit` when available, for example `deployedCommit`.

**Step 4: Run test to verify it passes**

Run: `node --test backend-node-v1/tests/security-hardening.test.mjs`
Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/security-hardening.test.mjs
git commit -m "ops: expose deployed backend commit"
```

### Task 3: Prepare the production server for git-controlled deploys

**Files:**
- Create on server: `/opt/streetstamps/backend-node-v1-repo`
- Preserve on server: `/opt/streetstamps/backend-node-v1/.env`
- Preserve on server: `/opt/streetstamps/backend-node-v1/data`
- Preserve on server: `/opt/streetstamps/backend-node-v1/media`

**Step 1: Create a production backup**

Run on server:

```bash
cp -R /opt/streetstamps/backend-node-v1 /opt/streetstamps/backend-node-v1.backup.$(date +%Y%m%d_%H%M%S)
```

Expected: a timestamped full backup exists before migration

**Step 2: Create the git working tree**

Run on server:

```bash
git clone https://github.com/cyberoff00/streetstamp.git /opt/streetstamps/backend-node-v1-repo
```

Expected: clean git checkout succeeds

**Step 3: Pin the checkout to the intended branch or commit**

Run on server:

```bash
git -C /opt/streetstamps/backend-node-v1-repo checkout <branch-or-commit>
git -C /opt/streetstamps/backend-node-v1-repo rev-parse HEAD
```

Expected: checkout resolves to the intended deploy source

**Step 4: Dry-run the deploy sync**

Run on server:

```bash
bash scripts/deploy_backend_from_git.sh --dry-run
```

Expected: output shows tracked backend files to sync and excluded runtime paths

**Step 5: Commit**

No git commit on the server. Record the deployed commit in the verification notes.

### Task 4: Switch production deploys to the new git-controlled flow

**Files:**
- Modify on server runtime tree via deploy script: `/opt/streetstamps/backend-node-v1`
- Verify running container: `streetstamps-node-v1`

**Step 1: Run the deploy script**

Run on server:

```bash
REPO_DIR=/opt/streetstamps/backend-node-v1-repo \
TARGET_DIR=/opt/streetstamps/backend-node-v1 \
bash /opt/streetstamps/backend-node-v1-repo/scripts/deploy_backend_from_git.sh
```

Expected: backend files sync, `api` rebuild completes, deployed commit marker is written

**Step 2: Verify container health**

Run on server:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep streetstamps-node-v1
curl -sS http://127.0.0.1:18080/v1/health
```

Expected: container is healthy and health JSON includes deployed commit metadata

**Step 3: Verify critical API paths**

Run on server:

```bash
curl -sS -i http://127.0.0.1:18080/v1/health
curl -sS -i -X POST http://127.0.0.1:18080/v1/profile/setup -H 'Content-Type: application/json' -d '{}'
```

Expected:
- `/v1/health` returns `200`
- `/v1/profile/setup` no longer returns `404`

**Step 4: Record the deployed git revision**

Run on server:

```bash
cat /opt/streetstamps/backend-node-v1/.deployed-git-commit
git -C /opt/streetstamps/backend-node-v1-repo status --short
```

Expected:
- deployed commit file matches the git checkout revision
- repo checkout is clean or intentionally understood

**Step 5: Commit**

```bash
git add docs/plans/2026-03-14-production-git-controlled-backend-deploy.md
git commit -m "docs: plan git-controlled production backend deploy"
```
