# Single Legacy Email Reverify Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow only `yinterestingy@163.com` to be re-registered through the modern email verification flow even if a legacy account still occupies that email in historical data.

**Architecture:** Keep the change local to the self-hosted auth register path. Add a targeted legacy-email bypass helper that recognizes this one configured recovery email only when the existing record is legacy-only, then let modern registration overwrite the stale email index entry. Protect the behavior with a contract test that proves the current bug and the intended recovery path.

**Tech Stack:** Node.js, Express, file-backed JSON persistence, node:test/assert contract coverage

---

### Task 1: Capture the regression in a failing contract test

**Files:**
- Modify: `backend-node-v1/tests/auth-register.contract.mjs`

**Step 1: Write the failing test**

Add a scenario with:
- a pre-seeded legacy user at `yinterestingy@163.com`
- an `emailIndex` entry pointing at that legacy user
- no `email_password` auth identity for that email
- a registration request for the same email that should succeed

Assert:
- response is `200`
- response includes `emailVerificationRequired: true`
- persisted `emailIndex["yinterestingy@163.com"]` now points to the new user
- a new `email_password` identity exists and is unverified

**Step 2: Run test to verify it fails**

Run: `node backend-node-v1/tests/auth-register.contract.mjs`

Expected: FAIL because `/v1/auth/register` still returns `409 email already exists`

### Task 2: Implement the minimal targeted bypass

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Add a helper**

Create a helper that returns true only when:
- the requested email matches `yinterestingy@163.com`
- `db.emailIndex[email]` points to an existing user
- that user has no `email_password` auth identity for the same email

**Step 2: Apply the helper in register flow**

Change `/v1/auth/register` so:
- real modern accounts still return `409`
- the targeted legacy-only email is allowed through
- successful registration overwrites `db.emailIndex[email]` with the new UID

**Step 3: Keep the change narrow**

Do not alter login, resend verification, Firebase migration, or any other email handling paths.

### Task 3: Verify the fix

**Files:**
- Verify: `backend-node-v1/tests/auth-register.contract.mjs`
- Verify: `backend-node-v1/tests/auth-verify-email.contract.mjs`

**Step 1: Run the focused register contract**

Run: `node backend-node-v1/tests/auth-register.contract.mjs`

Expected: PASS

**Step 2: Run adjacent verification coverage**

Run: `node backend-node-v1/tests/auth-verify-email.contract.mjs`

Expected: PASS

**Step 3: Review diff**

Run: `git diff -- backend-node-v1/server.js backend-node-v1/tests/auth-register.contract.mjs docs/plans/2026-03-13-single-legacy-email-reverify-implementation.md`

Expected: Only the targeted helper, test, and plan changes are present
