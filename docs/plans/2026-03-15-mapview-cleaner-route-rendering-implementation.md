# MapView Cleaner Route Rendering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `MapView` route lines render with a cleaner, thinner style while preserving the current route color and ensuring zoom changes visibly affect line thickness.

**Architecture:** Extract the `MapView` route width math into a small testable helper, then slim the renderer layer multipliers used by the active map route. Keep the existing route segmentation and color selection intact, and refresh overlays when camera altitude changes enough that the current zoom level should use different stroke widths.

**Tech Stack:** Swift, SwiftUI, MapKit, XCTest

---

### Task 1: Extract and test the route width policy

**Files:**
- Create: `StreetStampsTests/MapViewRouteRenderStyleTests.swift`
- Modify: `StreetStamps/MapView.swift`

**Step 1: Write the failing test**

Add tests that assert:
- route width becomes smaller at higher camera altitude
- walk mode is slightly wider than transit mode at the same altitude
- the cleaner style returns thinner values than the previous baseline

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/MapViewRouteRenderStyleTests`
Expected: FAIL because the new helper does not exist yet.

**Step 3: Write minimal implementation**

In `StreetStamps/MapView.swift`, extract a small helper that:
- computes base route width from camera altitude
- applies per-travel-mode multipliers
- returns the thinner core/halo/frequency widths used by renderers

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MapViewRouteRenderStyleTests.swift
git commit -m "test: cover cleaner map route width policy"
```

### Task 2: Apply the cleaner renderer treatment in MapView

**Files:**
- Modify: `StreetStamps/MapView.swift`

**Step 1: Write the failing test**

Extend the width-policy tests so they assert the chosen halo and core ratios remain bounded and lightweight, matching the intended clean rendering profile.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/MapViewRouteRenderStyleTests`
Expected: FAIL because the renderer style constants are still too heavy.

**Step 3: Write minimal implementation**

Update `rendererFor overlay` so:
- the main route core uses the new thinner widths
- the halo becomes much lighter and subtler
- the frequency layer is removed or reduced to a barely visible accent
- the live tail stays visually compatible with the thinner route

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MapViewRouteRenderStyleTests.swift
git commit -m "feat: slim active map route rendering"
```

### Task 3: Refresh route overlays when zoom changes

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MapViewRouteRenderStyleTests.swift`

**Step 1: Write the failing test**

Add a small test around the altitude-bucketing or refresh-threshold helper so zoom-level changes that cross a bucket request a renderer refresh while tiny camera jitters do not.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/MapViewRouteRenderStyleTests`
Expected: FAIL because no refresh-threshold helper exists yet.

**Step 3: Write minimal implementation**

In `StreetStamps/MapView.swift`:
- track the last applied zoom style bucket or altitude tier
- on `regionDidChangeAnimated`, refresh route overlays when the bucket changes
- avoid unnecessary overlay churn during tiny zoom movements

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MapViewRouteRenderStyleTests.swift
git commit -m "fix: refresh map route width on zoom"
```

### Task 4: Verify the final rendering behavior

**Files:**
- Modify: `StreetStamps/MapView.swift` if final tuning is still needed after verification

**Step 1: Run targeted tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/MapViewRouteRenderStyleTests`
Expected: PASS.

**Step 2: Run a broader smoke test**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/MapAppearanceSettingsTests`
Expected: PASS.

**Step 3: Do manual zoom verification**

Open the app, enter the active map view, and verify:
- the route looks cleaner at default zoom
- pinching out makes the route visibly slimmer
- color remains unchanged
- dashed segments and live tail still read clearly

**Step 4: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MapViewRouteRenderStyleTests.swift docs/plans/2026-03-15-mapview-cleaner-route-rendering-design.md docs/plans/2026-03-15-mapview-cleaner-route-rendering-implementation.md
git commit -m "refactor: clean up map route rendering"
```
