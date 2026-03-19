# MapView AllTrails Route Style Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an AllTrails-style outlined live route and an in-map 3-mode surface switcher to the tracking `MapView`, while keeping dark/light appearance as a separate concern.

**Architecture:** Introduce a new `MapSurfaceMode` preference in `MapAppearanceSettings`, keep the existing appearance enum for UI style, and move live route styling in `MapView` onto explicit route palette tokens that vary by surface mode. The first pass updates only the live tracking map so we can tune the visual system before propagating it to other map surfaces.

**Tech Stack:** Swift, SwiftUI, UIKit, MapKit, XCTest, UserDefaults

---

### Task 1: Lock down map mode configuration before UI work

**Files:**
- Modify: `StreetStamps/ThemeManager.swift`

**Step 1: Add the new map surface mode model**

Introduce a `MapSurfaceMode` enum with:

- `standard`
- `outdoor`
- `satellite`

Give it a storage key and a resolver that defaults to `outdoor`.

**Step 2: Extend `MapAppearanceSettings`**

Add helpers for:

- resolving the current `MapSurfaceMode`
- mapping each mode to `MKMapType`
- keeping the existing dark/light interface-style behavior intact

Do not rename or repurpose the current appearance enum for this task.

**Step 3: Add route palette token types**

Create a small token model in `ThemeManager.swift` that can describe the live route appearance for a given combination of:

- `MapSurfaceMode`
- current appearance style
- gap versus solid route
- tail versus main route

Prefer a centralized token struct over more one-off renderer constants.

**Step 4: Build to catch compile issues**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`

Expected: The project compiles with the new surface mode model in place, even though `MapView` does not use it yet.

**Step 5: Commit**

```bash
git add StreetStamps/ThemeManager.swift
git commit -m "feat: add map surface mode tokens"
```

### Task 2: Add a focused test for persisted map surface mode

**Files:**
- Create: `StreetStampsTests/MapAppearanceSettingsTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- an unknown stored surface mode resolves to `outdoor`
- each `MapSurfaceMode` maps to the intended `MKMapType`

Keep the test narrow and deterministic so it can run without UI harnesses.

**Step 2: Run the focused test**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/MapAppearanceSettingsTests`

Expected: FAIL if the surface mode mapping or defaulting behavior is not wired correctly yet.

**Step 3: Adjust the production code minimally**

If needed, tighten the `MapAppearanceSettings` helpers so the tests pass without adding UI-specific logic.

**Step 4: Re-run the focused test**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/ThemeManager.swift StreetStampsTests/MapAppearanceSettingsTests.swift
git commit -m "test: cover map surface mode settings"
```

### Task 3: Add the in-map 3-way surface mode control

**Files:**
- Modify: `StreetStamps/MapView.swift`

**Step 1: Find the map overlay controls section**

Locate the existing floating controls in `MapView` and identify a stable insertion point near the top-right map tools area.

**Step 2: Add persisted surface mode state**

Bind `MapView` to the new `MapSurfaceMode` preference using `@AppStorage`, separate from the existing appearance state.

**Step 3: Add the segmented floating control**

Implement a compact floating picker with labels:

- `Std`
- `Outdoor`
- `Sat`

The control should:

- immediately update the surface mode
- feel native to the existing map chrome
- avoid obscuring the primary tracking content

**Step 4: Verify the control compiles and appears**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`

Expected: PASS with the new overlay control visible in the live tracking screen.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift
git commit -m "feat: add live map surface mode picker"
```

### Task 4: Move the MKMapView bridge onto the new surface mode

**Files:**
- Modify: `StreetStamps/MapView.swift`

**Step 1: Update `JourneyMKMapView` inputs**

Pass the selected `MapSurfaceMode` into the `JourneyMKMapView` bridge rather than deriving the basemap entirely from the old appearance storage.

**Step 2: Apply basemap and UI style separately**

Update `applyAppearance(on:)` so:

- `map.mapType` is controlled by `MapSurfaceMode`
- `overrideUserInterfaceStyle` still comes from the existing appearance setting

**Step 3: Verify live switching behavior**

Ensure `updateUIView` reapplies the selected mode and that changing the picker updates the current `MKMapView` instance without requiring a full screen reload.

**Step 4: Run a build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`

Expected: PASS with no regressions in the bridge lifecycle.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift
git commit -m "feat: separate map surface from appearance"
```

### Task 5: Refactor the route renderer to explicit outline/glow/core tokens

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/ThemeManager.swift`

**Step 1: Write the failing renderer-oriented tests**

If the project already has a practical renderer test harness, add a small unit test that exercises route token selection for:

- solid route in `standard`
- solid route in `satellite`
- dashed route in `outdoor`

If no good harness exists, skip direct renderer tests and rely on token-level tests plus manual verification notes in the plan execution.

**Step 2: Add explicit route palette tokens**

Create token outputs that define:

- outline color and width multiplier
- glow color and width multiplier
- frequency or mid-layer treatment if still needed
- core color and width multiplier
- tail color and width multiplier

**Step 3: Update `rendererFor overlay`**

Replace the current softer layer math with a clearer AllTrails-style stack:

- outline
- glow
- core

Keep dashed behavior and existing altitude-based width scaling.

**Step 4: Re-run build and focused tests**

Run:

- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/MapAppearanceSettingsTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/ThemeManager.swift StreetStamps/MapView.swift StreetStampsTests/MapAppearanceSettingsTests.swift
git commit -m "feat: add outlined live route styling"
```

### Task 6: Preserve live-tail emphasis and incremental overlay ordering

**Files:**
- Modify: `StreetStamps/MapView.swift`

**Step 1: Review overlay ordering after the renderer refactor**

Check the incremental overlay update path in `syncOverlays(on:segments:liveTail:)` to make sure the live tail still gets removed and re-added above the route overlays when needed.

**Step 2: Tune tail tokens**

Make the tail slightly brighter and slightly more prominent than the main route core without becoming visually noisy.

**Step 3: Build again**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`

Expected: PASS.

**Step 4: Manual verification**

In the simulator or on-device, verify:

- the tail stays visually above the route after new points arrive
- `satellite` keeps the route readable
- dashed segments are still distinct from solid segments

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift
git commit -m "fix: keep live tail emphasized across map modes"
```

### Task 7: Run final verification for the first-pass scope

**Files:**
- Modify: none unless verification reveals issues

**Step 1: Run the focused test target**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/MapAppearanceSettingsTests`

Expected: PASS.

**Step 2: Run a final build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj`

Expected: PASS.

**Step 3: Inspect the working tree**

Run: `git status --short`

Expected: Only:

- `StreetStamps/ThemeManager.swift`
- `StreetStamps/MapView.swift`
- `StreetStampsTests/MapAppearanceSettingsTests.swift`

plus any plan docs created for this feature.

**Step 4: Document manual verification notes**

Record whether live switching, route readability, and tail layering all behaved correctly on `standard`, `outdoor`, and `satellite`.

**Step 5: Commit**

```bash
git add StreetStamps/ThemeManager.swift StreetStamps/MapView.swift StreetStampsTests/MapAppearanceSettingsTests.swift docs/plans/2026-03-19-mapview-alltrails-route-style-design.md docs/plans/2026-03-19-mapview-alltrails-route-style-implementation.md
git commit -m "docs: plan mapview alltrails route style"
```
