# Lifelog Footprint Zoom Threshold Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Lifelog switch into footprint mode at a slightly farther zoom level.

**Architecture:** The change stays inside `LifelogRenderModeSelector`, which already decides whether the Lifelog map is in near footprint mode. Tests in `LifelogRenderModeSelectorTests` define the threshold behavior so the render pipeline does not need structural changes.

**Tech Stack:** Swift, SwiftUI, MapKit, XCTest

---

### Task 1: Lock the new near-mode threshold in tests

**Files:**
- Modify: `StreetStampsTests/LifelogRenderModeSelectorTests.swift`

**Step 1: Write the failing test**

Add a test that creates a region with `latitudeDelta` and `longitudeDelta` of `0.05` and expects `LifelogRenderModeSelector.isNearMode(_:)` to return `true`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderModeSelectorTests`

Expected: the new near-mode assertion fails because the current threshold is smaller.

**Step 3: Write minimal implementation**

Update the near-mode span constants in `StreetStamps/LifelogView.swift` so `0.05` is included in near mode and a slightly larger span still returns `false`.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: the selector tests pass.

**Step 5: Commit**

Skip commit in the current workspace unless the unrelated dirty-tree changes are resolved first.

### Task 2: Verify no wider render logic changed

**Files:**
- Review: `StreetStamps/LifelogView.swift`

**Step 1: Confirm mode routing still uses selector only**

Check that `isNearFootprintMode`, `farRouteSegments`, and `footprintRuns` still depend only on `LifelogRenderModeSelector.isNearMode(_:)`.

**Step 2: Run focused validation**

If simulator access is available, re-run the selector test target. Otherwise, record the sandbox limitation and note that the code path change is intentionally isolated to the selector constants.
