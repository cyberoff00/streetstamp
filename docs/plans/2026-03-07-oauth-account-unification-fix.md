# OAuth Account Unification Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make OAuth login resolve back to the user's existing account, support legacy OAuth mappings, and safely merge mistaken empty OAuth accounts instead of creating new empty accounts.

**Architecture:** Keep the current `uid`-centric model, but centralize OAuth account resolution into a helper flow that checks modern OAuth keys, legacy hashed keys, and verified email mappings in a deterministic order. Add a conservative merge path that only folds a mistaken OAuth account into the intended account when the mistaken account is structurally empty, then persist the modern OAuth key so later logins are stable.

**Tech Stack:** Node.js, Express, built-in `node:test`, JSON file persistence, existing `backend-node-v1/server.js`

---

### Task 1: Add Regression Tests For OAuth Resolution

**Files:**
- Create: `backend-node-v1/tests/oauth-account-unification.test.mjs`
- Modify: `backend-node-v1/package.json`

**Step 1: Write the failing test**

Add tests that boot the backend against a temporary `DATA_FILE` and monkey-patch a deterministic OAuth identity response. Cover:

- legacy `oauthIndex` key (`provider:hashSHA256(idToken)`) returns the old `uid`
- verified email account gets reused instead of creating a second account
- mistaken empty OAuth account gets merged into the intended existing account
- non-empty conflicting account does not get auto-merged

**Step 2: Run test to verify it fails**

Run: `cd backend-node-v1 && node --test tests/oauth-account-unification.test.mjs`

Expected: FAIL because current OAuth login only checks `provider:subject` and does not merge mistaken empty accounts.

**Step 3: Expose the new test in package scripts**

Update `backend-node-v1/package.json` so the new regression test can be run directly and from `npm test`.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `cd backend-node-v1 && npm test`

Expected: FAIL, with the new OAuth regression test showing the incorrect current behavior.

**Step 5: Commit**

```bash
git add backend-node-v1/tests/oauth-account-unification.test.mjs backend-node-v1/package.json
git commit -m "test: add oauth account unification regression coverage"
```

### Task 2: Implement OAuth Resolution And Safe Merge Helpers

**Files:**
- Modify: `backend-node-v1/server.js`
- Test: `backend-node-v1/tests/oauth-account-unification.test.mjs`

**Step 1: Write the minimal helper surface**

In `backend-node-v1/server.js`, add focused helpers for:

- modern OAuth key generation: `provider:subject`
- legacy OAuth key generation: `provider:hashSHA256(idToken)`
- checking whether an account is structurally empty and safe to merge
- moving email / OAuth indexes from mistaken account to target account when safe
- resolving the intended login target from modern key, legacy key, or verified email

**Step 2: Implement the smallest code to satisfy the tests**

Update `POST /v1/auth/oauth` to:

1. verify provider and token as before
2. resolve `uid` by modern key first
3. fall back to legacy hashed key
4. fall back to verified email account
5. create a new account only if no prior identity matches
6. when a mistaken empty OAuth account exists, merge it conservatively into the intended account
7. always persist the modern OAuth key to the resolved account

**Step 3: Run targeted test to verify it passes**

Run: `cd backend-node-v1 && node --test tests/oauth-account-unification.test.mjs`

Expected: PASS.

**Step 4: Run adjacent backend tests for regression coverage**

Run: `cd backend-node-v1 && node tests/journey-migrate.contract.mjs`

Expected: PASS.

Run: `cd backend-node-v1 && node tests/postcard-api.contract.mjs`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/oauth-account-unification.test.mjs
git commit -m "fix: unify oauth logins with legacy account mappings"
```

### Task 3: Verify Full Backend Test Surface

**Files:**
- Modify: `backend-node-v1/package.json` if needed for `npm test`
- Test: `backend-node-v1/tests/postcard-rules.test.mjs`
- Test: `backend-node-v1/tests/oauth-account-unification.test.mjs`
- Test: `backend-node-v1/tests/journey-migrate.contract.mjs`
- Test: `backend-node-v1/tests/postcard-api.contract.mjs`

**Step 1: Ensure `npm test` covers the intended built-in tests**

If needed, update `backend-node-v1/package.json` so `npm test` includes both unit-style tests:

- `tests/postcard-rules.test.mjs`
- `tests/oauth-account-unification.test.mjs`

**Step 2: Run the full verified command**

Run: `cd backend-node-v1 && npm test`

Expected: PASS.

**Step 3: Run contract checks**

Run: `cd backend-node-v1 && node tests/journey-migrate.contract.mjs`

Expected: PASS.

Run: `cd backend-node-v1 && node tests/postcard-api.contract.mjs`

Expected: PASS.

**Step 4: Review resulting diff for scope**

Confirm only the OAuth unification fix, tests, and any required script adjustments changed.

**Step 5: Commit**

```bash
git add backend-node-v1/package.json backend-node-v1/server.js backend-node-v1/tests/oauth-account-unification.test.mjs
git commit -m "test: verify oauth account unification backend coverage"
```
