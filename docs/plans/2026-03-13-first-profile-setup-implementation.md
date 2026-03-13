# First Profile Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a one-time post-registration/profile-setup flow for brand new email and Apple accounts, and make nicknames globally unique with historical duplicate migration.

**Architecture:** Extend backend auth/profile responses with a first-setup flag and a dedicated profile setup endpoint, then gate iOS post-auth navigation on that flag. Reuse existing avatar/loadout systems and app theme so the first-time setup screen feels native to the current StreetStamps experience rather than a bolt-on flow.

**Tech Stack:** SwiftUI, XCTest, Node.js/Express, existing JSON/PG persistence helpers, contract tests

---

### Task 1: Define backend contract for first-time setup state

**Files:**
- Modify: `backend-node-v1/tests/auth-register.contract.mjs`
- Modify: `backend-node-v1/tests/auth-apple.contract.mjs`
- Modify: `backend-node-v1/tests/firebase-auth-profile.contract.mjs`

**Step 1: Write the failing tests**

Add assertions that:

- New registration/auth payloads include `needsProfileSetup === true`
- First Apple-created account includes `needsProfileSetup === true`
- Existing/repeated sign-ins include `needsProfileSetup === false`
- Profile payloads include `profileSetupCompleted`

**Step 2: Run test to verify it fails**

Run: `node backend-node-v1/tests/auth-register.contract.mjs`
Expected: FAIL because `needsProfileSetup` is missing or incorrect

Run: `node backend-node-v1/tests/auth-apple.contract.mjs`
Expected: FAIL because new/existing Apple auth responses are not differentiated

**Step 3: Write minimal implementation**

Modify `backend-node-v1/server.js` to:

- Add `profileSetupCompleted` to user defaults
- Add `needsProfileSetup` to auth response DTOs
- Set `needsProfileSetup` from `!user.profileSetupCompleted`
- Mark pre-existing users as completed during migration/bootstrap

**Step 4: Run test to verify it passes**

Run:
- `node backend-node-v1/tests/auth-register.contract.mjs`
- `node backend-node-v1/tests/auth-apple.contract.mjs`

Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/auth-register.contract.mjs backend-node-v1/tests/auth-apple.contract.mjs backend-node-v1/tests/firebase-auth-profile.contract.mjs
git commit -m "feat: add first profile setup auth contract"
```

### Task 2: Enforce unique nicknames and migrate historical duplicates

**Files:**
- Modify: `backend-node-v1/tests/firebase-auth-profile.contract.mjs`
- Modify: `backend-node-v1/tests/firebase-auth.test.mjs`
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing tests**

Add tests that:

- `PATCH /v1/profile/display-name` returns `409` when another user already owns the nickname
- Historical users loaded with the same display name are rewritten to `Name`, `Name2`, `Name3`

**Step 2: Run test to verify it fails**

Run: `node backend-node-v1/tests/firebase-auth-profile.contract.mjs`
Expected: FAIL because duplicate names are still accepted or historical duplicates are unchanged

**Step 3: Write minimal implementation**

Modify `backend-node-v1/server.js` to:

- Introduce a helper that checks display-name ownership across users
- Reuse that helper for display-name updates and first-setup submission
- Add startup migration to renumber duplicate historical names using direct numeric suffixes

**Step 4: Run test to verify it passes**

Run: `node backend-node-v1/tests/firebase-auth-profile.contract.mjs`
Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/firebase-auth-profile.contract.mjs backend-node-v1/tests/firebase-auth.test.mjs
git commit -m "feat: enforce unique display names"
```

### Task 3: Add backend profile-setup completion endpoint

**Files:**
- Modify: `backend-node-v1/tests/firebase-auth-profile.contract.mjs`
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing test**

Add a contract test for `POST /v1/profile/setup` that:

- Accepts `displayName` and `loadout`
- Persists both
- Sets `profileSetupCompleted === true`
- Returns updated profile data

**Step 2: Run test to verify it fails**

Run: `node backend-node-v1/tests/firebase-auth-profile.contract.mjs`
Expected: FAIL because endpoint does not exist

**Step 3: Write minimal implementation**

Modify `backend-node-v1/server.js` to add:

- `POST /v1/profile/setup`
- Validation for unique display name and valid loadout
- Persisted `profileSetupCompleted = true`

**Step 4: Run test to verify it passes**

Run: `node backend-node-v1/tests/firebase-auth-profile.contract.mjs`
Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/tests/firebase-auth-profile.contract.mjs
git commit -m "feat: add profile setup completion endpoint"
```

### Task 4: Expose first-setup auth state in iOS session models

**Files:**
- Modify: `StreetStampsTests/BackendAPIClientAuthErrorTests.swift`
- Modify: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/UserScopedProfileStateStore.swift`

**Step 1: Write the failing tests**

Add tests that:

- Decode `needsProfileSetup` from `BackendAuthResponse`
- Persist/read per-user pending setup state in `UserScopedProfileStateStore`
- Keep existing auth session behavior intact

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/BackendAPIClientAuthErrorTests -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests`
Expected: FAIL because the new field/state is missing

**Step 3: Write minimal implementation**

Modify the Swift models/stores to:

- Decode and store `needsProfileSetup`
- Track a per-user pending first-setup flag in `UserScopedProfileStateStore`
- Set/clear that flag from `UserSessionStore.applyAuth`

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/BackendAPIClient.swift StreetStamps/Usersessionstore.swift StreetStamps/UserScopedProfileStateStore.swift StreetStampsTests/BackendAPIClientAuthErrorTests.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift
git commit -m "feat: track pending first profile setup on ios"
```

### Task 5: Build the one-time setup UI with existing app styling

**Files:**
- Create: `StreetStamps/FirstProfileSetupView.swift`
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/EquipmentView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hant.lproj/Localizable.strings`
- Test: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Write the failing test**

Add a view/state-level test that confirms new users with pending setup are routed into the setup UI instead of straight to the app.

**Step 2: Run test to verify it fails**

Run a focused `xcodebuild test` command for the chosen test target.
Expected: FAIL because no setup UI or routing exists

**Step 3: Write minimal implementation**

Implement:

- `FirstProfileSetupView` using `FigmaTheme`, `RobotRendererView`, and a simplified loadout editor
- Nickname field with inline validation/error presentation
- Save CTA that submits both nickname and loadout
- Auth-entry presentation logic that shows the view after first-time auth only

Prefer extracting reusable loadout controls from `EquipmentView` only where necessary to avoid duplicating catalog logic.

**Step 4: Run test to verify it passes**

Run the focused `xcodebuild test` command again
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/FirstProfileSetupView.swift StreetStamps/AuthEntryView.swift StreetStamps/EquipmentView.swift StreetStamps/ProfileView.swift StreetStamps/en.lproj/Localizable.strings StreetStamps/zh-Hans.lproj/Localizable.strings StreetStamps/zh-Hant.lproj/Localizable.strings StreetStampsTests/ProfileSceneInteractionStateTests.swift
git commit -m "feat: add first profile setup screen"
```

### Task 6: Wire setup completion to backend profile persistence

**Files:**
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/FirstProfileSetupView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Test: `StreetStampsTests/BackendAPIClientAuthErrorTests.swift`
- Test: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`

**Step 1: Write the failing tests**

Add tests covering:

- New API client call for `POST /v1/profile/setup`
- Successful setup clears pending local state
- Returned display name/loadout overwrite local placeholders

**Step 2: Run test to verify it fails**

Run the focused iOS test command for the touched test classes.
Expected: FAIL because completion wiring is missing

**Step 3: Write minimal implementation**

Implement:

- `BackendAPIClient.completeProfileSetup(...)`
- Session-store helper to clear pending setup state after success
- Local `AppStorage` / loadout synchronization from the returned profile

**Step 4: Run test to verify it passes**

Run the same focused iOS tests again
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/BackendAPIClient.swift StreetStamps/Usersessionstore.swift StreetStamps/FirstProfileSetupView.swift StreetStamps/ProfileView.swift StreetStampsTests/BackendAPIClientAuthErrorTests.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift
git commit -m "feat: persist first profile setup completion"
```

### Task 7: Run final verification

**Files:**
- Verify only

**Step 1: Run backend verification**

Run:
- `node backend-node-v1/tests/auth-register.contract.mjs`
- `node backend-node-v1/tests/auth-apple.contract.mjs`
- `node backend-node-v1/tests/firebase-auth-profile.contract.mjs`

Expected: PASS

**Step 2: Run iOS verification**

Run:
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/BackendAPIClientAuthErrorTests -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests`

Expected: PASS

**Step 3: Sanity-check changed files**

Run:
- `git diff --stat`
- `git diff -- backend-node-v1/server.js StreetStamps/AuthEntryView.swift StreetStamps/Usersessionstore.swift`

Expected: only intended first-setup/nickname changes are present

**Step 4: Commit**

```bash
git add backend-node-v1/server.js StreetStamps/BackendAPIClient.swift StreetStamps/Usersessionstore.swift StreetStamps/UserScopedProfileStateStore.swift StreetStamps/AuthEntryView.swift StreetStamps/FirstProfileSetupView.swift StreetStamps/EquipmentView.swift StreetStamps/ProfileView.swift StreetStamps/en.lproj/Localizable.strings StreetStamps/zh-Hans.lproj/Localizable.strings StreetStamps/zh-Hant.lproj/Localizable.strings backend-node-v1/tests/auth-register.contract.mjs backend-node-v1/tests/auth-apple.contract.mjs backend-node-v1/tests/firebase-auth-profile.contract.mjs StreetStampsTests/BackendAPIClientAuthErrorTests.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift StreetStampsTests/ProfileSceneInteractionStateTests.swift docs/plans/2026-03-13-first-profile-setup-design.md docs/plans/2026-03-13-first-profile-setup-implementation.md
git commit -m "feat: add first-time profile setup flow"
```
