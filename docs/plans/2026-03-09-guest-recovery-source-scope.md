# Guest Recovery Source Scope Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Broaden automatic startup recovery so current-device `guest_*` buckets are discoverable without a `sourceDevice` match, while keeping legacy `account_*` recovery device-scoped.

**Architecture:** Refactor `UserSessionStore` recovery-source selection into separate guest and account candidate paths. Keep `GuestDataRecoveryService` merge semantics unchanged so the behavior change is isolated to source discovery and covered by targeted tests.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Add focused recovery-source tests

**Files:**
- Modify: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing test**

- Add a test that simulates:
  - a recoverable local `guest_*` source physically present on disk
  - binding metadata for the same guest with a mismatched `sourceDevice`
  - expectation: the `guest_*` source is still selected for automatic recovery
- Add a test that simulates:
  - a recoverable `account_*` source
  - guest-account binding with matching `guestID` but mismatched `sourceDevice`
  - expectation: the `account_*` source is not selected

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests`

Expected:

- FAIL because current source discovery still requires `sourceDevice` for both source classes

**Step 3: Write minimal implementation**

- Add only the test scaffolding and assertions needed to prove the two source-discovery rules

**Step 4: Run test to verify it passes once implementation lands**

Run the same command after Task 2.

Expected:

- PASS for the new recovery-source selection coverage

**Step 5: Commit**

```bash
git add StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "test: cover guest recovery source scoping"
```

### Task 2: Split guest and legacy account source discovery

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`

**Step 1: Write the failing test**

- Use the tests from Task 1 as the red bar for this implementation

**Step 2: Run test to verify it fails**

Run the Task 1 XCTest command.

Expected:

- FAIL for the new guest/account source-scope expectations

**Step 3: Write minimal implementation**

- Refactor `scopedRecoverySourceUserIDs` and `scopedRecoverySourceUserIDsWorker` so:
  - guest candidates come from local sandbox discovery of recoverable `guest_*` directories
  - account candidates continue to come from guest-account bindings filtered by `guestID` and `sourceDevice`
- Keep ordering through the existing recoverable-source sorting helper
- Do not change `GuestDataRecoveryService.recover(...)` or `GuestRecoveryOptions.conservativeAuto`

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests`

Expected:

- PASS

**Step 5: Commit**

```bash
git add StreetStamps/Usersessionstore.swift StreetStampsTests/GuestDataRecoveryServiceTests.swift
git commit -m "fix: widen guest recovery source discovery"
```

### Task 3: Verify startup safety and document the behavior

**Files:**
- Modify: `docs/plans/2026-03-07-local-profile-auth-decoupling-design.md`
- Modify: `docs/plans/2026-03-09-guest-recovery-source-scope-design.md`

**Step 1: Run verification**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -derivedDataPath build/DerivedDataGuestRecovery
```

Expected:

- Tests pass
- Build succeeds

**Step 2: Document rollout notes**

- Record that guest discovery is now based on current-device local presence rather than `sourceDevice`-matched bindings
- Record that legacy `account_*` recovery remains device-scoped
- Record that startup recovery still uses conservative non-destructive merge behavior

**Step 3: Commit**

```bash
git add docs/plans/2026-03-07-local-profile-auth-decoupling-design.md docs/plans/2026-03-09-guest-recovery-source-scope-design.md
git commit -m "docs: clarify guest recovery source rules"
```
