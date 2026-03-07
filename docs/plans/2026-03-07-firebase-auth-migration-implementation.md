# Firebase Auth Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace custom app authentication with Firebase Auth, preserve the existing business account behind `yinterestingy@gmail.com`, and keep guest mode local-only.

**Architecture:** The iOS app authenticates with Firebase and sends Firebase ID tokens to the existing backend. The backend verifies Firebase tokens with Firebase Admin SDK, resolves a backend-owned `appUserId` via a new identity mapping layer, and preserves one historical business user by binding `yinterestingy@gmail.com` to the existing legacy account. Guest mode remains entirely local and no longer triggers cloud migration.

**Tech Stack:** Swift, SwiftUI, Firebase Auth for iOS, Google Sign-In, Sign in with Apple, Node.js, Firebase Admin SDK, XCTest, Node test scripts

---

### Task 1: Document Firebase configuration inputs in app and backend

**Files:**
- Modify: `StreetStamps/BackendConfig.swift`
- Modify: `backend-node-v1/package.json`
- Modify: `backend-node-v1/server.js`
- Create: `docs/plans/2026-03-07-firebase-auth-setup-notes.md`

**Step 1: Write the failing setup note**

- Add a short setup note listing the required Firebase values:
  - iOS `GoogleService-Info.plist`
  - Firebase project bundle ID alignment
  - backend service account or application default credentials
  - preserved legacy email `yinterestingy@gmail.com`
  - preserved legacy backend `appUserId`

**Step 2: Run validation to verify missing config surfaces clearly**

- Review app/backend config access points and confirm there is no silent fallback that would hide missing Firebase configuration.

**Step 3: Write minimal implementation**

- Extend config helpers so the app and backend have explicit placeholders or env var reads for Firebase migration.

**Step 4: Re-run validation**

- Confirm the app/backend would now fail fast with clear configuration errors.

**Step 5: Commit**

```bash
git add StreetStamps/BackendConfig.swift backend-node-v1/package.json backend-node-v1/server.js docs/plans/2026-03-07-firebase-auth-setup-notes.md
git commit -m "docs: add firebase auth setup requirements"
```

### Task 2: Add backend Firebase identity verification and mapping tests

**Files:**
- Create: `backend-node-v1/tests/firebase-auth.test.mjs`
- Modify: `backend-node-v1/tests/helpers/google-oauth-stub.cjs`
- Modify: `backend-node-v1/tests/journey-migrate.contract.mjs`

**Step 1: Write the failing test**

- Add coverage for:
  - verified Firebase token creates a new backend identity mapping
  - repeated requests with the same Firebase UID reuse the same backend user
  - Firebase token with email `yinterestingy@gmail.com` binds to the preserved legacy backend user
  - unauthenticated requests still fail cleanly

**Step 2: Run test to verify it fails**

Run:

```bash
npm run test:api-contract
node backend-node-v1/tests/firebase-auth.test.mjs
```

Expected:

- the new Firebase auth test fails because no Firebase verification or mapping layer exists yet

**Step 3: Write minimal implementation**

- Add a Firebase token verification abstraction in `backend-node-v1/server.js`.
- Add identity mapping storage and lookup helpers.
- Add preserved-email binding logic for `yinterestingy@gmail.com`.

**Step 4: Run tests to verify they pass**

Run:

```bash
npm run test:api-contract
node backend-node-v1/tests/firebase-auth.test.mjs
```

Expected:

- contract tests still pass where applicable
- Firebase auth mapping tests pass

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/firebase-auth.test.mjs backend-node-v1/tests/helpers/google-oauth-stub.cjs backend-node-v1/tests/journey-migrate.contract.mjs
git commit -m "feat: verify firebase auth tokens in backend"
```

### Task 3: Switch backend request auth from custom tokens to Firebase ID tokens

**Files:**
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Create: `StreetStamps/FirebaseAuthSession.swift`
- Test: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`

**Step 1: Write the failing test**

- Add or extend tests around authenticated request construction so the backend client must source its bearer token from Firebase session state instead of custom backend access tokens.

**Step 2: Run test to verify it fails**

- Run the focused XCTest target if available, or record the lack of a stable isolated auth test target.

**Step 3: Write minimal implementation**

- Introduce a Firebase session helper that exposes:
  - current Firebase UID
  - current email
  - current verification state
  - async current ID token retrieval
- Remove dependency on backend refresh token management in `BackendAPIClient`.
- Update `UserSessionStore.Session.account` to store Firebase-backed identity fields rather than backend refresh credentials.

**Step 4: Run tests to verify they pass**

- Re-run the focused Swift tests if executable in the current scheme.

**Step 5: Commit**

```bash
git add StreetStamps/BackendAPIClient.swift StreetStamps/Usersessionstore.swift StreetStamps/FirebaseAuthSession.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift
git commit -m "refactor: source backend auth from firebase session"
```

### Task 4: Migrate email/password auth UI to Firebase flows

**Files:**
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/GoogleSignInService.swift`
- Modify: `StreetStamps/AppleSignInService.swift`
- Create: `StreetStamps/EmailVerificationView.swift`
- Create: `StreetStamps/FirebaseEmailAuthService.swift`

**Step 1: Write the failing UI-focused checks**

- Define focused tests or manual acceptance checks for:
  - email/password registration sends verification and does not treat the user as fully ready until verified
  - forgot-password sends Firebase reset email
  - Google sign-in signs into Firebase
  - Apple sign-in signs into Firebase

**Step 2: Run checks to verify the current implementation fails**

- Confirm the current UI still calls custom backend email and OAuth routes and lacks verification/reset behavior.

**Step 3: Write minimal implementation**

- Replace email/password register/login calls with Firebase Auth equivalents.
- Add resend verification and refresh verification state handling.
- Convert Google and Apple token flows into Firebase credential sign-ins.
- Route unverified users into a verification-required state.

**Step 4: Run checks to verify the new flows behave correctly**

- Re-run the focused tests if present, otherwise perform manual simulator checks for each provider and email flow.

**Step 5: Commit**

```bash
git add StreetStamps/AuthEntryView.swift StreetStamps/GoogleSignInService.swift StreetStamps/AppleSignInService.swift StreetStamps/EmailVerificationView.swift StreetStamps/FirebaseEmailAuthService.swift
git commit -m "feat: move app auth flows to firebase"
```

### Task 5: Remove guest-to-cloud migration behavior

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/JourneyCloudMigrationService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add coverage proving that signing into an account from guest mode:
  - does not upload guest content
  - does not archive guest content into account-scoped cloud state
  - does not leave a pending guest cloud migration marker

**Step 2: Run test to verify it fails**

- Run the focused guest/session tests if available.

**Step 3: Write minimal implementation**

- Remove or gate off guest cloud migration side effects in `applyAuth`.
- Ensure app startup does not attempt automatic guest-to-account cloud migration for Firebase accounts.

**Step 4: Run tests to verify they pass**

- Re-run the focused guest/session tests.

**Step 5: Commit**

```bash
git add StreetStamps/Usersessionstore.swift StreetStamps/JourneyCloudMigrationService.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "refactor: keep guest mode local only"
```

### Task 6: Add backend current-user resolution integration checks

**Files:**
- Modify: `backend-node-v1/tests/postcard-api.contract.mjs`
- Modify: `backend-node-v1/tests/oauth-account-unification.test.mjs`
- Create: `backend-node-v1/tests/firebase-auth-profile.contract.mjs`

**Step 1: Write the failing test**

- Add backend integration coverage that:
  - authenticated Firebase requests can load `/v1/profile/me`
  - business APIs operate with resolved backend user identity
  - the preserved legacy email resolves to the same historical business account across repeated sign-ins

**Step 2: Run test to verify it fails**

Run:

```bash
npm run test:api-contract
node backend-node-v1/tests/firebase-auth-profile.contract.mjs
```

Expected:

- the new profile contract test fails before the Firebase-backed auth middleware is fully wired

**Step 3: Write minimal implementation**

- Wire the Firebase identity resolver into the backend auth middleware used by profile and business routes.

**Step 4: Run tests to verify they pass**

Run:

```bash
npm run test:api-contract
node backend-node-v1/tests/firebase-auth-profile.contract.mjs
```

Expected:

- authenticated profile and business route tests pass with Firebase-backed identity

**Step 5: Commit**

```bash
git add backend-node-v1/tests/postcard-api.contract.mjs backend-node-v1/tests/oauth-account-unification.test.mjs backend-node-v1/tests/firebase-auth-profile.contract.mjs backend-node-v1/server.js
git commit -m "test: cover firebase-backed business identity"
```

### Task 7: Verify build, auth flows, and migration behavior

**Files:**
- Modify: `docs/plans/2026-03-07-firebase-auth-migration-implementation.md`

**Step 1: Run Swift tests if available**

- Run targeted auth/session tests or document the current scheme limitations.

**Step 2: Run backend test suite**

Run:

```bash
npm run test:api-contract
node backend-node-v1/tests/firebase-auth.test.mjs
node backend-node-v1/tests/firebase-auth-profile.contract.mjs
```

Expected:

- all Firebase auth backend tests pass

**Step 3: Run iOS build verification**

- Build the app target with the configured Firebase SDK and confirm compile success.

**Step 4: Manual smoke verification**

- Verify email registration -> verification email sent
- verify sign-in blocks until email is verified
- verify forgot-password sends reset email
- verify Google sign-in works
- verify Apple sign-in works
- verify `yinterestingy@gmail.com` lands on the preserved historical account
- verify guest data remains local and unchanged after account sign-in

**Step 5: Update implementation notes**

- Record any remaining rollout risks, especially around Firebase console setup and the preserved-email binding.
