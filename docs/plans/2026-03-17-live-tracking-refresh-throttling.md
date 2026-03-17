# Live Tracking Refresh Throttling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce foreground live-tracking redraw and coordinate-driven snapshot churn without removing the live feel of the tracking screen.

**Architecture:** Keep the existing `TrackingService -> MapView -> JourneyStore` flow, but tighten the cadence at two points: map render debounce in `TrackingModeConfig` and coordinate snapshot persistence in `MapView`. Immediate persistence paths remain unchanged so finish, exit, and user-triggered edits still flush promptly.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest, xcodebuild

---

### Task 1: Document the refresh policy in code-facing tests

**Files:**
- Create: `StreetStampsTests/LiveTrackingRefreshPolicyTests.swift`
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/TrackingMode.swift`

**Step 1: Write the failing test**

Add tests that assert:
- coordinate-driven snapshot cadence only allows persistence after `5s`
- sport mode render debounce is `0.16s`
- daily mode render debounce is `0.5s`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveTrackingRefreshPolicyTests`
Expected: FAIL because the policy type or tuned values do not exist yet.

**Step 3: Write minimal implementation**

Add a small helper that answers whether a coordinate tick should trigger snapshot persistence, then update the render debounce values.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStamps/TrackingMode.swift StreetStampsTests/LiveTrackingRefreshPolicyTests.swift
git commit -m "tune live tracking refresh cadence"
```

### Task 2: Apply the snapshot cadence inside MapView

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/LiveTrackingRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Extend the policy test if needed so coordinate ticks before the interval do not request persistence, while first tick and interval-crossing ticks do.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveTrackingRefreshPolicyTests`
Expected: FAIL with an assertion showing coordinate ticks still persist too eagerly.

**Step 3: Write minimal implementation**

Track the last coordinate snapshot time inside `MapView` and only call `persistSnapshot(.coordsTick)` when the cadence policy allows it.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/LiveTrackingRefreshPolicyTests.swift
git commit -m "throttle live coordinate snapshots"
```

### Task 3: Verify the tracking flow still behaves

**Files:**
- Test: `StreetStampsTests/LiveTrackingRefreshPolicyTests.swift`
- Test: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`

**Step 1: Run focused regression tests**

Run:

```bash
xcodebuild test -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -only-testing:StreetStampsTests/LiveTrackingRefreshPolicyTests \
  -only-testing:StreetStampsTests/TrackingServiceResumeLocationTests
```

Expected: PASS with zero failures.

**Step 2: Review behavior-sensitive code**

Confirm immediate persistence paths for `.memoryAdded`, `.finish`, `.exitToHome`, and explicit mode changes are unchanged.

**Step 3: Commit**

```bash
git add docs/plans/2026-03-17-live-tracking-refresh-throttling-design.md docs/plans/2026-03-17-live-tracking-refresh-throttling.md
git commit -m "document live tracking refresh throttling"
```
