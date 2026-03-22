# Email Verification Landing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a browser-facing `GET /verify-email` endpoint that consumes the emailed token, marks the email as verified, and returns a minimal success or failure HTML page.

**Architecture:** Keep the existing token issuance and `POST /v1/auth/verify-email` behavior intact. Add one shared verification helper so both the JSON API and the browser route use the same token validation and persistence logic, then render a small inline HTML response for success, invalid, used, or expired tokens.

**Tech Stack:** Node.js, Express, existing file/PostgreSQL-backed auth state, contract tests in plain Node.

---

### Task 1: Add the failing browser-route contract coverage

**Files:**
- Modify: `backend-node-v1/tests/auth-verify-email.contract.mjs`

**Step 1: Write the failing test**

Extend the contract test to:
- request `GET /verify-email?token=<issued token>` and expect `200`, HTML content, and a success phrase
- verify the persisted identity becomes `emailVerified === true`
- request `GET /verify-email?token=<same token>` and expect `400` with a failure phrase
- request `GET /verify-email?token=<expired token>` and expect `400` with a failure phrase

**Step 2: Run test to verify it fails**

Run: `node tests/auth-verify-email.contract.mjs`

Expected: FAIL because `GET /verify-email` does not exist yet.

### Task 2: Implement the minimal browser-facing route

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Extract shared verification logic**

Create a helper that:
- validates token presence
- loads the token record
- rejects invalid, used, or expired tokens with explicit status/message
- marks the token used and identity verified on success

**Step 2: Keep the existing JSON route working**

Make `POST /v1/auth/verify-email` call the shared helper and preserve its JSON response shape.

**Step 3: Add `GET /verify-email`**

Return `text/html; charset=utf-8` and render a minimal page with:
- success title/body for verified tokens
- failure title/body for invalid/used/expired tokens
- copy telling the user to return to the app and re-send the email if needed

### Task 3: Verify and deploy

**Files:**
- Modify: `/opt/streetstamps/backend-node-v1/server.js` on the server via deployment sync

**Step 1: Run local verification**

Run: `node tests/auth-verify-email.contract.mjs`

Expected: PASS

**Step 2: Deploy updated backend**

Copy the updated `server.js` to the server deployment directory and restart the `api` container.

**Step 3: Smoke test browser flow**

Use a fresh registration to obtain a token, then request:
- `GET /verify-email?token=<fresh token>` and expect success HTML
- `GET /verify-email?token=<same token>` and expect failure HTML
