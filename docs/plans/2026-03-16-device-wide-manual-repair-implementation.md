# Device-Wide Manual Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove automatic restore/recovery from normal flows and make Settings data repair import all on-device journey roots without reviving deleted journeys.

**Architecture:** Startup and auth-change flows stop calling automatic recovery/restore helpers. The Settings repair entrypoint performs an explicit device-wide scan, imports missing journeys into the active profile, consults a deleted-journey tombstone list, and rebuilds the city cache from the repaired journey set.

**Tech Stack:** Swift, SwiftUI, XCTest, file-backed user storage

---

### Task 1: Lock down startup behavior

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Write the failing tests**

- Replace the startup auto-import expectations with assertions that `bootstrapFileSystemAsync()` does not import historical guest/account roots.
- Add assertions that startup logic no longer performs automatic restore-trigger assumptions.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests`

Expected: FAIL because bootstrap still auto-imports historical roots.

**Step 3: Write minimal implementation**

- Remove automatic recovery calls from bootstrap.
- Remove automatic restore calls from app startup and active-profile switch flows.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

### Task 2: Persist deleted-journey tombstones

**Files:**
- Modify: `StreetStamps/StoragePath.swift`
- Create: `StreetStamps/DeletedJourneyStore.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Test: `StreetStampsTests/DeletedJourneyStoreTests.swift`

**Step 1: Write the failing test**

- Add a test proving `discardJourneys` records deleted IDs.

**Step 2: Run test to verify it fails**

Run: targeted test command for `DeletedJourneyStoreTests`.

Expected: FAIL because no tombstone file exists yet.

**Step 3: Write minimal implementation**

- Add a file-backed deleted-journey store.
- Record IDs during discard/delete operations.

**Step 4: Run test to verify it passes**

Run the targeted deleted-journey tests.

Expected: PASS.

### Task 3: Make Settings repair import all on-device data safely

**Files:**
- Create: `StreetStamps/ManualDeviceRepairService.swift`
- Modify: `StreetStamps/SettingsView+DataRepair.swift`
- Modify: `StreetStamps/CurrentUserRepairService.swift`
- Test: `StreetStampsTests/ManualDeviceRepairServiceTests.swift`

**Step 1: Write the failing tests**

- Add a test proving manual repair imports journeys from multiple device roots into the active profile.
- Add a test proving tombstoned journey IDs are skipped.

**Step 2: Run test to verify it fails**

Run: targeted test command for `ManualDeviceRepairServiceTests`.

Expected: FAIL because the Settings repair path only repairs the active profile and does not scan device-wide.

**Step 3: Write minimal implementation**

- Discover all device user roots.
- Import missing journeys into the active profile using the existing file recovery service.
- Skip tombstoned IDs.
- Rebuild index and city cache from the repaired set.

**Step 4: Run test to verify it passes**

Run the targeted manual-repair tests.

Expected: PASS.

### Task 4: Verify targeted regressions

**Files:**
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`
- Test: `StreetStampsTests/DeletedJourneyStoreTests.swift`
- Test: `StreetStampsTests/ManualDeviceRepairServiceTests.swift`

**Step 1: Run focused verification**

Run the targeted XCTest commands for the touched suites.

**Step 2: Review results**

- Confirm no startup auto-import remains.
- Confirm deleted journeys are tombstoned.
- Confirm manual repair imports device-wide sources but skips deleted IDs.
