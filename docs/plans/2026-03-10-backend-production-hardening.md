# Backend Production Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden the backend and production configuration so the beta can run with controlled origins, baseline security headers, request limits, and clearer deployment guidance.

**Architecture:** Keep the single Node service and add internal middleware for origin validation, headers, limits, and operational health. Pair the app changes with production env templates, Nginx config, and safer verification docs so the deployed stack matches the code-level hardening.

**Tech Stack:** Node.js, Express, Docker Compose, Nginx, shell verification scripts

---

### Task 1: Add backend regression coverage

**Files:**
- Create: `backend-node-v1/tests/security-hardening.test.mjs`
- Modify: `backend-node-v1/package.json`

**Step 1: Write the failing test**

- Cover allowed origin CORS success, disallowed origin rejection, security headers on `/v1/health`, auth rate limiting, and oversized JSON rejection.

**Step 2: Run test to verify it fails**

Run: `node --test tests/security-hardening.test.mjs`
Expected: FAIL because the current server still allows wildcard CORS and has no rate limiting.

**Step 3: Write minimal implementation**

- Add only the middleware and config needed to satisfy the test expectations.

**Step 4: Run test to verify it passes**

Run: `node --test tests/security-hardening.test.mjs`
Expected: PASS

### Task 2: Harden the Express server

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing test**

- Reuse Task 1 coverage rather than adding duplicate tests.

**Step 2: Run test to verify it fails**

Run: `node --test tests/security-hardening.test.mjs`
Expected: FAIL

**Step 3: Write minimal implementation**

- Disable `x-powered-by`
- Add configurable allowed origins
- Add app security headers
- Add request-size config and error handling
- Add targeted in-memory rate limiters
- Expand `/v1/health`

**Step 4: Run test to verify it passes**

Run: `node --test tests/security-hardening.test.mjs`
Expected: PASS

### Task 3: Add production config and deployment guidance

**Files:**
- Create: `backend-node-v1/.env.production.example`
- Create: `docs/ops/nginx-streetstamps.conf`
- Modify: `backend-node-v1/docker-compose.yml`
- Modify: `docs/LAUNCH_CHECKLIST.md`
- Modify: `scripts/preflight_check.sh`
- Modify: `scripts/e2e_smoke.sh`

**Step 1: Write the failing test**

- Not applicable; validate through targeted script checks and manual file review.

**Step 2: Run verification for current behavior**

Run: `./scripts/preflight_check.sh`
Expected: Existing warnings about incomplete production config remain.

**Step 3: Write minimal implementation**

- Add explicit production env knobs and safer compose placeholders
- Add Nginx template
- Separate read-only verification from mutating smoke notes

**Step 4: Run verification**

Run: `./scripts/preflight_check.sh`
Expected: Script still passes and reflects the new configuration expectations.

### Task 4: Final verification

**Files:**
- Verify only

**Step 1: Run backend syntax and tests**

Run: `node --check backend-node-v1/server.js`
Expected: PASS

Run: `node --test backend-node-v1/tests/security-hardening.test.mjs`
Expected: PASS

**Step 2: Run existing backend regression tests**

Run: `npm test`
Expected: PASS

**Step 3: Run repo preflight**

Run: `./scripts/preflight_check.sh`
Expected: PASS

**Step 4: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/package.json backend-node-v1/tests/security-hardening.test.mjs backend-node-v1/.env.production.example backend-node-v1/docker-compose.yml docs/ops/nginx-streetstamps.conf docs/LAUNCH_CHECKLIST.md scripts/preflight_check.sh scripts/e2e_smoke.sh docs/plans/2026-03-10-backend-production-hardening-design.md docs/plans/2026-03-10-backend-production-hardening.md
git commit -m "feat: harden backend production configuration"
```
