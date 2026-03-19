# Chain Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove three fallback-driven behaviors so rendering, deletion sync, and motion lifecycle each follow one explicit main chain.

**Architecture:** The implementation removes synthetic render bridging, introduces an explicit deletion-sync failure store, and makes `StreetStampsApp` the sole owner of motion activity run policy. The plan keeps changes local to the affected modules and validates each behavior with failing tests first.

**Tech Stack:** Swift, SwiftUI, XCTest, Combine

---

### Task 1: Remove synthetic lifelog adjacency bridges

**Files:**
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`

**Step 1: Write the failing test**

Add a test in `StreetStampsTests/LifelogRenderSnapshotTests.swift` that builds a day snapshot from two separate runs and asserts the far-route output contains only the segments generated from those runs, with no extra dashed bridge between them.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/LifelogRenderSnapshotTests`

Expected: FAIL because the snapshot builder still injects an adjacent dashed bridge.

**Step 3: Write minimal implementation**

Remove the adjacency bridge insertion path from `StreetStamps/LifelogRenderSnapshot.swift` so the builder only returns segments derived from recorded runs.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/LifelogRenderSnapshotTests`

Expected: PASS.

### Task 2: Make journey deletion migration failures explicit

**Files:**
- Create: `StreetStamps/JourneyDeletionSyncFailureStore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps.xcodeproj/project.pbxproj`
- Test: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`

**Step 1: Write the failing test**

Add a test in `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift` that simulates a migration deletion failure and asserts the app-side deletion handler records a failure entry instead of discarding the error.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/JourneyCloudIncrementalSyncTests`

Expected: FAIL because the delete hook currently uses `try?` and exposes no failure state.

**Step 3: Write minimal implementation**

Create a small observable failure store that records `journeyID` plus a short error summary for migration deletion failures. Update the delete hook in `StreetStamps/StreetStampsApp.swift` to clear any previous failure for a journey before retrying deletion, and record a new failure when migration deletion throws.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/JourneyCloudIncrementalSyncTests`

Expected: PASS.

### Task 3: Make `StreetStampsApp` the only motion policy owner

**Files:**
- Modify: `StreetStamps/TrackingService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/MotionActivityPolicyTests.swift`

**Step 1: Write the failing test**

Add a focused test around the app-owned motion policy sync path, or extend `MotionActivityPolicyTests` with a coverage case that proves passive lifelog enablement plus authorization is interpreted from the app-owned state path.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/MotionActivityPolicyTests`

Expected: FAIL because `TrackingService` still owns part of the `setShouldRun` write path.

**Step 3: Write minimal implementation**

Remove the motion policy sync helper and call sites from `StreetStamps/TrackingService.swift`. Keep `StreetStampsApp.syncMotionActivityPolicy()` as the single write path, using `lifelogStore.isEnabled`, tracking state, and authorization state as the only inputs.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/MotionActivityPolicyTests`

Expected: PASS.

### Task 4: Run focused regression verification

**Files:**
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Test: `StreetStampsTests/JourneyCloudIncrementalSyncTests.swift`
- Test: `StreetStampsTests/MotionActivityPolicyTests.swift`

**Step 1: Run the focused suite**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/JourneyCloudIncrementalSyncTests -only-testing:StreetStampsTests/MotionActivityPolicyTests`

Expected: PASS for all targeted tests.

**Step 2: Review diff for main-chain integrity**

Check that:
- No synthetic adjacent run bridge code remains
- No `try?` remains in the migration deletion path
- No `TrackingService` call site remains for `setShouldRun`

**Step 3: Commit**

Commit after verification with a message such as:

```bash
git add StreetStamps StreetStampsTests StreetStamps.xcodeproj docs/plans
git commit -m "refactor: remove fallback-driven tracking chain paths"
```
