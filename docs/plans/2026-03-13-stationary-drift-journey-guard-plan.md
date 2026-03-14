# Stationary Drift Journey Guard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent long indoor GPS drift from being preserved as a valid journey when the user stayed still.

**Architecture:** Tighten active tracking's stationary recovery logic so weak GPS does not easily flip back into "moving", then add a journey-finalization validity gate so obviously drift-only sessions are marked too short and hidden. Cover both layers with focused regression tests.

**Tech Stack:** Swift, XCTest, CoreLocation, MapKit

---

### Task 1: Add regression tests for drift-only journeys

**Files:**
- Modify: `StreetStampsTests/LifelogStoreBehaviorTests.swift`
- Create: `StreetStampsTests/JourneyFinalizerTests.swift`

**Step 1: Write the failing test**

Add a test that finalizes a route with many points but only tiny start/end displacement and low total credibility, and assert it becomes `isTooShort == true`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyFinalizerTests`

Expected: FAIL because current finalizer accepts the route.

**Step 3: Add a second failing test if needed**

Add a test proving a real short-but-moving route is still kept valid.

**Step 4: Run targeted tests again**

Expected: first fails for the right reason; second may pass or fail depending on current behavior.

### Task 2: Implement stricter stationary drift guards

**Files:**
- Modify: `StreetStamps/TrackingService.swift`

**Step 1: Implement minimal logic**

Make movement exit from stationary mode require stronger evidence when accuracy is weak, so a single indoor jump does not resume route recording.

**Step 2: Keep change scoped**

Do not alter unrelated filtering or rendering behavior.

**Step 3: Run focused tests**

Run the same targeted test command plus any affected tracking tests if present.

### Task 3: Reject drift-only completed journeys

**Files:**
- Modify: `StreetStamps/JourneyFinalizer.swift`
- Modify: `StreetStamps/MapView.swift` if helper access is needed

**Step 1: Implement minimal validity gate**

Use route distance and start/end displacement to mark obviously stationary-drift sessions as `isTooShort`.

**Step 2: Preserve legitimate journeys**

Keep real moving journeys, even if short, out of the drift bucket.

**Step 3: Run targeted tests**

Run: `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyFinalizerTests`

Expected: PASS.

### Task 4: Verify end-to-end safety

**Files:**
- Modify: `StreetStampsTests/JourneyFinalizerTests.swift` if assertions need tightening

**Step 1: Run broader regression coverage**

Run:

```bash
xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyFinalizerTests -only-testing:StreetStampsTests/LifelogStoreBehaviorTests
```

Expected: PASS.

**Step 2: Review diff**

Confirm the change only affects drift suppression and invalid journey handling.
