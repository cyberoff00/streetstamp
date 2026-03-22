# Password Reset Landing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a browser-facing password reset landing route that can launch the existing app deep link and provides a fallback HTML page when the app does not open.

**Architecture:** Keep the existing reset token issuance and `POST /v1/auth/reset-password` API unchanged. Change reset emails to point at a new `GET /reset-password?token=...` route that renders a small HTML bridge page and attempts to redirect the browser to `streetstamps://reset-password?token=...`.

**Tech Stack:** Node.js, Express, existing auth token storage, plain Node contract tests.

---

### Task 1: Add failing contract coverage

**Files:**
- Modify: `backend-node-v1/tests/auth-password-reset.contract.mjs`

**Step 1: Write the failing test**

Extend the contract test to assert:
- password reset emails now contain `http://127.0.0.1:<port>/reset-password?token=...`
- `GET /reset-password?token=<token>` returns `200`, `text/html`, and includes the `streetstamps://reset-password?token=...` deep link
- `GET /reset-password?token=` or invalid token still returns HTML with a failure/help message

**Step 2: Run test to verify it fails**

Run: `node tests/auth-password-reset.contract.mjs`

Expected: FAIL because reset emails still use the app deep link directly and the browser route does not exist.

### Task 2: Implement the browser bridge

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Add HTML renderer for reset landing**

Render a minimal page that:
- shows a short title/body
- includes a button or link to `streetstamps://reset-password?token=...`
- runs a small script to try opening the app automatically

**Step 2: Change emailed reset links**

Generate reset email URLs as `${AUTH_LINK_BASE}/reset-password?token=...` while continuing to embed the same token.

**Step 3: Add `GET /reset-password`**

Validate token presence enough to build the deep link and return HTML. For missing/invalid tokens, render a small failure page with retry guidance instead of the launch page.

### Task 3: Verify and deploy

**Files:**
- Modify: `/opt/streetstamps/backend-node-v1/server.js` on the server via deployment sync

**Step 1: Run local verification**

Run: `node tests/auth-password-reset.contract.mjs`

Expected: PASS

**Step 2: Deploy updated backend**

Sync the updated `server.js` to the server and restart the running container.

**Step 3: Smoke test**

Verify:
- `GET /reset-password?token=invalid-token` returns failure HTML
- a known valid token returns launch HTML containing the `streetstamps://reset-password?token=...` deep link
