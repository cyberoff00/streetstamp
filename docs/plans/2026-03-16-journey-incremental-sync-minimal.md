# Journey Incremental Sync Minimal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move journey create/update/delete behavior onto incremental CloudKit sync so deleted journeys do not return from snapshot restore behavior.

**Architecture:** Keep local `JourneyStore` persistence unchanged and add a small injected sync hook layer for journey upsert/delete events. Route those hooks through `CloudKitSyncService` to `JourneyCloudKitSync`, and add a lightweight startup pull that merges remote journeys into the local store without depending on `ICloudSyncService`.

**Tech Stack:** Swift, Swift Concurrency, CloudKit, XCTest

---

### Task 1: Add failing tests for journey incremental hooks

**Files:**
- Modify: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`
- Test: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`

**Step 1: Write the failing test**

Add focused tests that verify:

- deleting a journey from `JourneyStore` invokes the incremental delete hook with that journey ID
- saving a completed journey invokes the incremental upsert hook with that journey ID

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyCloudIncrementalSyncTests`

Expected: FAIL because `JourneyStore` does not yet expose or call incremental sync hooks.

**Step 3: Write minimal implementation**

Add an injected hook container to `JourneyStore` and call it after local add/delete mutations.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm the focused tests pass.

### Task 2: Route journey hooks through CloudKit sync

**Files:**
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Test: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`

**Step 1: Write the failing test**

Add or extend tests to verify the app can install hooks without changing local persistence behavior.

**Step 2: Run test to verify it fails**

Run the same focused `xcodebuild test` command.

Expected: FAIL because the app does not yet wire `JourneyStore` changes to `CloudKitSyncService`.

**Step 3: Write minimal implementation**

Expose `syncJourneyUpsert`, `syncJourneyDeletion`, and `restoreJourneySnapshot` entry points on `CloudKitSyncService`, then install these hooks from `StreetStampsApp`.

**Step 4: Run test to verify it passes**

Run the same focused `xcodebuild` command and confirm PASS.

### Task 3: Add a startup incremental journey restore

**Files:**
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Test: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`

**Step 1: Write the failing test**

Add a focused test that verifies downloaded remote journeys can be merged into `JourneyStore` through a single restore entry point.

**Step 2: Run test to verify it fails**

Run the same focused `xcodebuild test` command.

Expected: FAIL because the restore path is not available yet.

**Step 3: Write minimal implementation**

Add a `mergeDownloadedJourneys` helper on `JourneyStore` and call the CloudKit restore entry point during app startup and user switching.

**Step 4: Run test to verify it passes**

Run the same focused `xcodebuild` command and confirm PASS.
