# Self-Hosted Auth Replacement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the in-progress Firebase production auth path with backend-owned email/password plus Apple auth, use Amazon SES for verification and password reset, and keep Firebase only as backup/reference.

**Architecture:** The Node backend becomes the sole runtime auth authority and stores users, auth identities, verification tokens, password reset tokens, and refresh tokens in PostgreSQL. The iOS app stops using Firebase for primary login, calls backend auth endpoints directly, and returns to backend-issued access and refresh tokens. Apple auth is verified server-side and attached to backend-owned identities with an explicit merge rule for real-email matches only.

**Tech Stack:** Swift, SwiftUI, Node.js, PostgreSQL, Amazon SES, Sign in with Apple, XCTest, Node integration tests

**Invariant:** This plan changes authentication only. It must not change `guestID` generation, device-local guest storage semantics, or the rule that guest data stays local-only unless a future explicit import feature is separately designed and approved.

---

### Task 1: Document the approved replacement direction and freeze Firebase as backup-only

**Files:**
- Create: `docs/plans/2026-03-07-self-hosted-auth-design.md`
- Modify: `docs/plans/2026-03-07-firebase-auth-migration-implementation.md`

**Step 1: Write the failing documentation gap**

- Add a migration note explaining that Firebase is no longer the target production auth architecture because mainland-compatible runtime auth cannot rely on Google/Firebase endpoints.

**Step 2: Review the current docs to verify the gap exists**

Run:

```bash
rg -n "Firebase becomes the only authentication provider|self-hosted" docs/plans
```

Expected:

- existing docs only describe Firebase as the primary auth target

**Step 3: Write minimal implementation**

- Add the approved design document.
- Add a short note in the Firebase implementation doc pointing future work to the self-hosted auth replacement plan.

**Step 4: Re-run the doc check**

Run:

```bash
rg -n "self-hosted auth|backup/reference" docs/plans
```

Expected:

- the new design is discoverable from the plans directory

**Step 5: Commit**

```bash
git add docs/plans/2026-03-07-self-hosted-auth-design.md docs/plans/2026-03-07-firebase-auth-migration-implementation.md
git commit -m "docs: add self-hosted auth replacement design"
```

### Task 2: Add PostgreSQL auth schema for backend-owned identities and tokens

**Files:**
- Modify: `backend-node-v1/server.js`
- Test: `backend-node-v1/tests/helpers/`
- Create: `backend-node-v1/tests/self-hosted-auth-schema.test.mjs`

**Step 1: Write the failing test**

- Add a backend test that expects PostgreSQL-backed auth tables or equivalent state records for:
  - `users`
  - `auth_identities`
  - `email_verification_tokens`
  - `password_reset_tokens`
  - `refresh_tokens`

**Step 2: Run test to verify it fails**

Run:

```bash
node --test backend-node-v1/tests/self-hosted-auth-schema.test.mjs
```

Expected:

- FAIL because the self-hosted auth schema does not exist yet

**Step 3: Write minimal implementation**

- Add schema creation and data access helpers in `backend-node-v1/server.js`.
- Keep changes scoped to auth storage only; do not refactor unrelated business tables yet.
- Do not alter guest/account data ownership logic while introducing the auth schema.

**Step 4: Run test to verify it passes**

Run:

```bash
node --test backend-node-v1/tests/self-hosted-auth-schema.test.mjs
```

Expected:

- PASS with all auth tables or stored structures initialized

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/self-hosted-auth-schema.test.mjs backend-node-v1/tests/helpers
git commit -m "feat: add self-hosted auth schema"
```

### Task 3: Implement email/password registration with strong password validation

**Files:**
- Modify: `backend-node-v1/server.js`
- Create: `backend-node-v1/tests/auth-register.contract.mjs`

**Step 1: Write the failing test**

- Add contract coverage for:
  - valid password is accepted
  - missing letter is rejected
  - missing number is rejected
  - missing special character is rejected
  - duplicate email is rejected
  - successful register creates an unverified email identity

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-register.contract.mjs
```

Expected:

- FAIL because the new register contract is not implemented

**Step 3: Write minimal implementation**

- Add `POST /v1/auth/register`.
- Normalize email input.
- Enforce approved password rules.
- Hash passwords with `argon2id`.
- Create the user and `email_password` identity with `email_verified = false`.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-register.contract.mjs
```

Expected:

- PASS for valid and invalid password cases

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/auth-register.contract.mjs
git commit -m "feat: add self-hosted email registration"
```

### Task 4: Implement SES-backed email verification flow

**Files:**
- Modify: `backend-node-v1/server.js`
- Modify: `backend-node-v1/package.json`
- Create: `backend-node-v1/tests/auth-verify-email.contract.mjs`

**Step 1: Write the failing test**

- Add coverage for:
  - registration creates a verification token
  - verification marks the identity as verified
  - expired token fails
  - reused token fails

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-verify-email.contract.mjs
```

Expected:

- FAIL because verification token issuance and confirmation do not exist yet

**Step 3: Write minimal implementation**

- Add SES mail-sending abstraction.
- Add `POST /v1/auth/verify-email`.
- Store only token hashes, not raw tokens.
- Make verification links single-use and expiring.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-verify-email.contract.mjs
```

Expected:

- PASS for successful and invalid verification cases

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/package.json backend-node-v1/tests/auth-verify-email.contract.mjs
git commit -m "feat: add SES-backed email verification"
```

### Task 5: Implement backend-issued login, refresh, and logout

**Files:**
- Modify: `backend-node-v1/server.js`
- Create: `backend-node-v1/tests/auth-session.contract.mjs`

**Step 1: Write the failing test**

- Add coverage for:
  - unverified email cannot fully log in
  - verified email can log in
  - refresh token issues a new access token
  - logout revokes the active refresh token

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-session.contract.mjs
```

Expected:

- FAIL because session issue/refresh/revocation are not wired for the new auth model

**Step 3: Write minimal implementation**

- Add `POST /v1/auth/login`, `POST /v1/auth/refresh`, and `POST /v1/auth/logout`.
- Hash refresh tokens at rest.
- Reuse the existing backend access-token model if it is sound; otherwise replace it with a simpler JWT design.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-session.contract.mjs
```

Expected:

- PASS for login, refresh, and logout

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/auth-session.contract.mjs
git commit -m "feat: add self-hosted auth sessions"
```

### Task 6: Implement forgot-password and reset-password via SES

**Files:**
- Modify: `backend-node-v1/server.js`
- Create: `backend-node-v1/tests/auth-password-reset.contract.mjs`

**Step 1: Write the failing test**

- Add coverage for:
  - forgot-password returns a generic success response
  - reset token is single-use
  - reset updates password hash
  - reset revokes existing refresh tokens

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-password-reset.contract.mjs
```

Expected:

- FAIL because password reset flows are not implemented

**Step 3: Write minimal implementation**

- Add `POST /v1/auth/forgot-password` and `POST /v1/auth/reset-password`.
- Use SES for outbound reset mail.
- Revoke active sessions when password is changed.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-password-reset.contract.mjs
```

Expected:

- PASS for issuance, reset, and revocation behavior

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/auth-password-reset.contract.mjs
git commit -m "feat: add self-hosted password reset"
```

### Task 7: Implement Apple auth exchange with approved merge rules

**Files:**
- Modify: `backend-node-v1/server.js`
- Modify: `StreetStamps/AppleSignInService.swift`
- Modify: `StreetStamps/AuthEntryView.swift`
- Create: `backend-node-v1/tests/auth-apple.contract.mjs`

**Step 1: Write the failing test**

- Add coverage for:
  - first-time Apple login creates a user
  - repeat Apple login reuses the same user
  - Apple real email matching an existing verified email identity merges into that user
  - Apple hidden email creates a separate user and does not merge

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-apple.contract.mjs
```

Expected:

- FAIL because Apple exchange and merge rules are not implemented

**Step 3: Write minimal implementation**

- Add `POST /v1/auth/apple` to verify Apple identity.
- Store the Apple `sub` in `auth_identities`.
- Update iOS Apple sign-in flow so the app sends Apple credentials to the backend instead of Firebase.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-apple.contract.mjs
```

Expected:

- PASS for reuse, merge, and hidden-email separation rules

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/auth-apple.contract.mjs StreetStamps/AppleSignInService.swift StreetStamps/AuthEntryView.swift
git commit -m "feat: add backend-owned apple auth"
```

### Task 8: Replace app email auth flows with backend-owned auth endpoints

**Files:**
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/EmailVerificationView.swift`

**Step 1: Write the failing test**

- Add or extend app auth checks to prove:
  - register calls the backend instead of Firebase
  - login uses backend-issued tokens
  - verification UI works with backend email verification
  - forgot-password calls the backend reset endpoint

**Step 2: Run test to verify it fails**

- Run the focused auth-related test target if available, or record manual checks that still show Firebase-bound behavior.

**Step 3: Write minimal implementation**

- Remove runtime dependency on `FirebaseEmailAuthService` from email flows.
- Return to backend token storage in `UserSessionStore`.
- Teach `BackendAPIClient` to use backend tokens again for authenticated API traffic.
- Preserve the existing `guestID` field and local guest namespace behavior.
- Do not add any guest-to-account upload, merge, or migration side effects.

**Step 4: Run checks to verify it passes**

- Run focused auth tests if executable.
- Otherwise perform manual simulator checks for register, verify, login, and forgot-password.

**Step 5: Commit**

```bash
git add StreetStamps/AuthEntryView.swift StreetStamps/Usersessionstore.swift StreetStamps/BackendAPIClient.swift StreetStamps/EmailVerificationView.swift
git commit -m "refactor: move email auth back to backend"
```

### Task 9: Remove Google sign-in from app and backend entry points

**Files:**
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/GoogleSignInService.swift`
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing check**

- Define a focused UI/backend check showing Google sign-in is still reachable from the app or backend.

**Step 2: Run check to verify it fails**

- Confirm Google sign-in entry points still exist.

**Step 3: Write minimal implementation**

- Remove Google sign-in button and related backend route handling from the production auth path.
- Keep any non-production helper code only if still needed for backups or migration scripts.

**Step 4: Run check to verify it passes**

- Confirm no production login path still references Google sign-in.

**Step 5: Commit**

```bash
git add StreetStamps/AuthEntryView.swift StreetStamps/GoogleSignInService.swift backend-node-v1/server.js
git commit -m "refactor: remove google sign-in from production auth"
```

### Task 10: Demote Firebase code to backup-only status

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/BackendConfig.swift`
- Modify: `backend-node-v1/docker-compose.yml`
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing check**

- Add a focused check that production startup still depends on Firebase auth config or Firebase token verification.

**Step 2: Run check to verify it fails**

- Confirm the app or backend still treats Firebase as a required production auth dependency.

**Step 3: Write minimal implementation**

- Gate Firebase setup behind backup-only or migration-only flags.
- Remove Firebase bearer-token verification from the production request path.
- Keep Firebase config only where historical inspection or offline migration utilities still need it.
- Reconfirm that disabling Firebase from production auth does not reintroduce guest/account migration behavior.

**Step 4: Run check to verify it passes**

- Confirm the production path works without Firebase runtime auth requirements.

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/BackendConfig.swift backend-node-v1/docker-compose.yml backend-node-v1/server.js
git commit -m "refactor: demote firebase to backup-only"
```

### Task 11: Verify end-to-end auth flows and rollout safety

**Files:**
- Modify: `docs/plans/2026-03-07-self-hosted-auth-implementation.md`

**Step 1: Write the failing verification checklist**

- Add a rollout checklist covering:
  - register
  - verify email
  - login
  - forgot password
  - reset password
  - Apple login with real email
  - Apple login with hidden email
  - logout
  - guest data remains local after register and login
  - account login does not auto-import guest data

**Step 2: Run verification to surface gaps**

Run:

```bash
npm run test:api-contract
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj
```

Expected:

- all backend contracts and app build checks complete without new failures

**Step 3: Write minimal implementation**

- Update the plan doc with actual rollout notes, unresolved risks, and any production config gaps discovered during verification.

**Step 4: Re-run verification**

Run:

```bash
npm run test:api-contract
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj
```

Expected:

- same commands pass after final cleanup

**Step 5: Commit**

```bash
git add docs/plans/2026-03-07-self-hosted-auth-implementation.md
git commit -m "docs: record self-hosted auth rollout verification"
```
