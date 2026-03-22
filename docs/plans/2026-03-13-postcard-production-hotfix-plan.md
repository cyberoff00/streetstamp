# Postcard Production Hotfix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the dynamic postcard quota backend logic to production so live behavior matches the current local implementation.

**Architecture:** Keep the hotfix minimal and backend-only. Verify the existing local implementation, test it locally, patch only the production backend files that participate in quota enforcement, rebuild the API container, and verify health plus deployed logic on the server.

**Tech Stack:** Node.js, Docker Compose, PostgreSQL-backed app state, production SSH deployment

---

### Task 1: Verify the local target behavior

**Files:**
- Read: `backend-node-v1/postcard-rules.js`
- Read: `backend-node-v1/server.js`
- Test: `backend-node-v1/tests/postcard-rules.test.mjs`
- Test: `backend-node-v1/tests/postcard-api.contract.mjs`

**Step 1: Run the postcard rules test suite**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: PASS

**Step 2: Run the postcard API contract test**

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: PASS

### Task 2: Patch the production backend safely

**Files:**
- Modify on server: `/opt/streetstamps/backend-node-v1/postcard-rules.js`
- Modify on server: `/opt/streetstamps/backend-node-v1/server.js`
- Backup on server: `/opt/streetstamps/backend-node-v1.bak.<timestamp>`

**Step 1: Create a timestamped backup of the current production backend directory**

**Step 2: Copy the validated local backend files to the production directory**

**Step 3: Confirm the live files now include `cityJourneyCount`, `perFriendQuota`, and `cityUniqueFriendQuota`**

### Task 3: Rebuild and restart the API container

**Files:**
- Use on server: `/opt/streetstamps/backend-node-v1/docker-compose.yml`

**Step 1: Rebuild the `api` service image**

Run on server: `docker compose build api`
Expected: build completes successfully

**Step 2: Restart the `api` service**

Run on server: `docker compose up -d api`
Expected: service restarts successfully

**Step 3: Confirm the container is healthy**

Run on server: `docker ps --format "table {{.Names}}\t{{.Status}}" | grep streetstamps-node-v1`
Expected: `streetstamps-node-v1` shows `healthy`

### Task 4: Verify production behavior

**Files:**
- Read on server: `/opt/streetstamps/backend-node-v1/postcard-rules.js`
- Read on server: `/opt/streetstamps/backend-node-v1/server.js`

**Step 1: Check deployed files**

Verify that:
- `postcard-rules.js` computes quotas from `cityJourneyCount`
- `server.js` parses `cityJourneyCount` in `/v1/postcards/send`

**Step 2: Check API health**

Run on server: `curl -fsS http://127.0.0.1:18080/v1/health`
Expected: successful health response

**Step 3: Summarize deployment state**

Report:
- local test results
- backup path used on the server
- container rebuild/restart outcome
- production verification evidence
