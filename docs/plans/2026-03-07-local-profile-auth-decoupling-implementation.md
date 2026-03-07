# Local Profile and Auth Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Decouple local device storage from authentication state so logout or temporary auth failure does not change the visible local data, while new-device login restores cloud-backed account data into the device's stable local profile.

**Architecture:** Introduce a stable `local_<deviceProfileID>` storage root for all runtime local stores, keep account identity as separate session state, and migrate legacy `guest_*` and `account_*` roots into the new local profile with conservative merge rules. Cloud sync and restore continue to use account auth, but they operate against the active local profile instead of selecting a different local root.

**Tech Stack:** Swift, SwiftUI, XCTest, file-based local storage, UserDefaults, existing backend profile and journey sync APIs

---

### Task 1: Add explicit local-profile runtime state

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`

**Step 1: Write the failing test**

- Add tests covering:
  - session store exposes a stable `activeLocalProfileID`
  - logout clears account auth state but preserves `activeLocalProfileID`
  - applying auth updates account state without changing `activeLocalProfileID`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests`

Expected:

- FAIL because the session store still derives runtime storage identity from `currentUserID`

**Step 3: Write minimal implementation**

- In `StreetStamps/Usersessionstore.swift`:
  - add persisted `activeLocalProfileID`
  - keep `accountUserID` and auth credentials separate
  - stop treating the auth user ID as the runtime local storage ID
- In `StreetStamps/StreetStampsApp.swift`:
  - initialize stores from `activeLocalProfileID`
  - stop rebinding stores on account-only auth changes

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected:

- PASS for the new local-profile/session-state tests

**Step 5: Commit**

```bash
git add StreetStamps/Usersessionstore.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift
git commit -m "refactor: separate local profile from auth session"
```

### Task 2: Add `local_*` storage-root support

**Files:**
- Modify: `StreetStamps/StoragePath.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add tests proving:
  - new runtime storage roots use `local_<deviceProfileID>`
  - logout no longer rebinds the app to `guest_*`
  - legacy `guest_*` and `account_*` remain discoverable as migration sources

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests`

Expected:

- FAIL because runtime storage still points to `guest_*` or `account_*`

**Step 3: Write minimal implementation**

- In `StreetStamps/StoragePath.swift`:
  - support the new `local_*` root convention through normal `userID` inputs
- In `StreetStamps/Usersessionstore.swift`:
  - create/load a stable local profile ID
  - expose helpers for legacy guest/account roots separately from the active local root

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected:

- PASS for the new local-root behavior

**Step 5: Commit**

```bash
git add StreetStamps/StoragePath.swift StreetStamps/Usersessionstore.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "feat: add stable local storage root"
```

### Task 3: Implement legacy-root migration into `local_*`

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/GuestDataRecoveryService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add migration coverage for:
  - existing guest-only install upgrades into `local_*`
  - existing account-only install upgrades into `local_*`
  - install with both roots merges unique data into `local_*`
  - migration marker prevents rerunning destructive work

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests`

Expected:

- FAIL because there is no one-time migration into a stable local root

**Step 3: Write minimal implementation**

- In `StreetStamps/Usersessionstore.swift`:
  - add upgrade bootstrap flow for `local_*`
  - discover legacy sources and select a base source
  - persist migration markers and imported-source metadata
- In `StreetStamps/GuestDataRecoveryService.swift`:
  - add merge helpers needed for conservative import into `local_*`
- In `StreetStamps/StreetStampsApp.swift`:
  - ensure the migration runs before runtime stores load from disk

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected:

- PASS for legacy import into `local_*`

**Step 5: Commit**

```bash
git add StreetStamps/Usersessionstore.swift StreetStamps/GuestDataRecoveryService.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "feat: migrate legacy local roots into stable profile"
```

### Task 4: Stop auth transitions from rebinding runtime stores

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/AccountCenterView.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add behavior coverage proving:
  - logout does not switch local storage roots
  - login failure does not switch local storage roots
  - verified/unverified auth state changes do not switch local storage roots

**Step 2: Run test to verify it fails**

Run the focused guest/session test command again.

Expected:

- FAIL because the app still reacts to auth identity changes as local-store rebind events

**Step 3: Write minimal implementation**

- In `StreetStamps/StreetStampsApp.swift`:
  - replace `onChange` listeners that rebind stores from `sessionStore.currentUserID`
  - only rebind stores when `activeLocalProfileID` changes
- In `StreetStamps/Usersessionstore.swift`:
  - make logout auth-only
- In `StreetStamps/AccountCenterView.swift`:
  - keep the existing logout UI but ensure the action only signs out the cloud identity

**Step 4: Run test to verify it passes**

Run the focused guest/session test command again.

Expected:

- PASS for logout/auth-only transitions

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/Usersessionstore.swift StreetStamps/AccountCenterView.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "refactor: keep local profile stable across auth changes"
```

### Task 5: Re-scope cloud download and merge to the active local profile

**Files:**
- Modify: `StreetStamps/JourneyCloudMigrationService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add tests proving:
  - cloud restore imports account data into the active `local_*`
  - cloud restore does not require an `account_*` local root
  - account logout does not remove restored local data

**Step 2: Run test to verify it fails**

Run the focused guest/session test command again.

Expected:

- FAIL because cloud import paths still assume auth-scoped local identity

**Step 3: Write minimal implementation**

- In `StreetStamps/JourneyCloudMigrationService.swift`:
  - operate on the current local profile root when reading/writing local data
- In `StreetStamps/StreetStampsApp.swift`:
  - call cloud restore after auth succeeds without changing the active local profile

**Step 4: Run test to verify it passes**

Run the focused guest/session test command again.

Expected:

- PASS for cloud-to-local restore semantics

**Step 5: Commit**

```bash
git add StreetStamps/JourneyCloudMigrationService.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "refactor: restore cloud data into active local profile"
```

### Task 6: Preserve profile state against local-profile changes only

**Files:**
- Modify: `StreetStamps/UserScopedProfileStateStore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`

**Step 1: Write the failing test**

- Add tests covering:
  - avatar/display-name state keys use the active local profile for runtime restoration
  - logout does not swap display state
  - future explicit local-profile change still swaps the scoped profile state correctly

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests`

Expected:

- FAIL because current profile-state switching is tied to auth identity changes

**Step 3: Write minimal implementation**

- In `StreetStamps/UserScopedProfileStateStore.swift`:
  - scope runtime profile-state transitions to the local profile identity
- In `StreetStamps/StreetStampsApp.swift`:
  - only call scoped profile-state switches when the active local profile changes

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected:

- PASS for local-profile-scoped avatar/display-state behavior

**Step 5: Commit**

```bash
git add StreetStamps/UserScopedProfileStateStore.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift
git commit -m "refactor: scope profile state to local profile"
```

### Task 7: Add startup and cross-device restore regression coverage

**Files:**
- Modify: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`
- Modify: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`
- Modify: `docs/plans/2026-03-07-local-profile-auth-decoupling-design.md`

**Step 1: Write the failing test**

- Add final regression coverage for:
  - app startup after logout still loads the same local data
  - app startup after login failure still loads the same local data
  - new-device login restores cloud-backed data into `local_*`

**Step 2: Run test to verify it fails**

Run both focused XCTest commands from Tasks 1 and 3.

Expected:

- FAIL until all startup and restore paths use the new model

**Step 3: Write minimal implementation**

- Fill any remaining gaps surfaced by the final regression tests
- Update the design doc if the implementation required any constrained adjustment

**Step 4: Run test to verify it passes**

Run both focused XCTest commands again.

Expected:

- PASS for the full local-profile/auth-decoupling flow

**Step 5: Commit**

```bash
git add StreetStampsTests/GuestDataRecoveryServiceTests.swift StreetStampsTests/UserScopedProfileStateStoreTests.swift docs/plans/2026-03-07-local-profile-auth-decoupling-design.md
git commit -m "test: lock local profile auth decoupling behavior"
```

### Task 8: Verify build behavior and document rollout constraints

**Files:**
- Modify: `docs/plans/2026-03-07-local-profile-auth-decoupling-implementation.md`
- Modify: `docs/plans/2026-03-07-local-profile-auth-decoupling-design.md`

**Step 1: Run verification**

Run:

```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -derivedDataPath build/DerivedDataLocalProfile
```

Expected:

- BUILD SUCCEEDED

**Step 2: Perform manual behavior checks**

- Launch a legacy install with data in `guest_*`
- Launch a legacy install with data in `account_*`
- Log in, log out, and restart the app
- Verify visible local data remains stable
- On a second simulator or device, log into the same account and verify cloud-backed data restores into the new `local_*`

**Step 3: Document rollout notes**

- Record any migration caveats
- Record whether legacy roots remain on disk for rollback safety
- Record any backend account-unification dependency that still must be resolved separately

**Step 4: Commit**

```bash
git add docs/plans/2026-03-07-local-profile-auth-decoupling-implementation.md docs/plans/2026-03-07-local-profile-auth-decoupling-design.md
git commit -m "docs: record local profile rollout verification"
```
