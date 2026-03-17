# Manual Lifelog CloudKit Restore Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Settings "Restore from iCloud" flow restore passive lifelog and daily mood from CloudKit using day-based batches, then rebuild the local render inputs.

**Architecture:** Keep the existing manual restore entry point in `SettingsView`, but extend it to call a new incremental CloudKit restore path for passive lifelog and mood after the legacy snapshot restore finishes. Add day-batch export/import helpers to `LifelogStore`, implement day-based `LifelogCloudKitSync` plus `LifelogMoodCloudKitSync`, and merge restored source data locally so existing render rebuild hooks continue to work.

**Tech Stack:** Swift, Swift Concurrency, CloudKit, XCTest

---

### Task 1: Add failing tests for day-batch lifelog restore helpers

**Files:**
- Modify: `StreetStampsTests/LifelogStoreBehaviorTests.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing test**

Add focused tests that verify:

- `LifelogStore` can export passive points grouped by `dayKey`
- `LifelogStore` can merge restored day batches and mood values back into local state

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `LifelogStoreBehaviorTests`.

Expected: FAIL because the export/merge helpers do not exist yet.

**Step 3: Write minimal implementation**

Add `snapshotPointsByDay`, `snapshotMoodByDay`, and `mergeCloudRestore` helpers to `LifelogStore`.

**Step 4: Run test to verify it passes**

Run the same focused command and confirm PASS, unless unrelated test-target build failures still block execution.

### Task 2: Implement day-based CloudKit sync for passive lifelog and mood

**Files:**
- Modify: `StreetStamps/LifelogCloudKitSync.swift`
- Create: `StreetStamps/LifelogMoodCloudKitSync.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing test**

Extend tests or add focused CloudKit-facing assertions for:

- day-based lifelog record IDs
- tombstone-aware mood restore payloads

**Step 2: Run test to verify it fails**

Run the same focused test command.

Expected: FAIL because current sync still uses month-level batches and has no mood module.

**Step 3: Write minimal implementation**

Refactor `LifelogCloudKitSync` to use one record per day and add a lightweight `LifelogMoodCloudKitSync` with tombstone support.

**Step 4: Run test to verify it passes**

Run the same focused command and confirm PASS if the shared test target is healthy.

### Task 3: Wire manual Settings restore through incremental lifelog recovery

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Modify: `StreetStamps/LifelogStore.swift`

**Step 1: Write the failing test**

Add a focused behavior test for the restore helper if it can be isolated without SwiftUI view tests.

**Step 2: Run test to verify it fails**

Run the same focused test command.

Expected: FAIL because manual restore does not call the incremental lifelog/mood recovery path yet.

**Step 3: Write minimal implementation**

Have `restoreFromICloudManually()` call the new CloudKit restore helper, then reload `LifelogStore` so existing revision/change observers rebuild tiles and render caches.

**Step 4: Run test to verify it passes**

Run focused verification and the app build command to confirm production code compiles.
