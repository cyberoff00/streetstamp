# Button Hit Target Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify high-frequency tap targets so visible button, card, and row surfaces are fully interactive across core StreetStamps screens.

**Architecture:** Introduce a shared `appFullSurfaceTapTarget` SwiftUI modifier with explicit shapes, then apply it to shared button-like components and audited high-traffic screens. Use a lightweight source-level coverage test to guard continued adoption in the selected files.

**Tech Stack:** SwiftUI, XCTest, source-file inspection tests

---

### Task 1: Add the shared tap-target modifier contract

**Files:**
- Create: `StreetStamps/AppFullSurfaceTapTarget.swift`
- Create: `StreetStampsTests/InteractiveSurfaceCoverageTests.swift`

**Step 1: Write the failing test**

Add a test that expects the new helper API to exist and audited files to reference `appFullSurfaceTapTarget(`.

**Step 2: Run test to verify it fails**

Run a focused `xcodebuild test` command for `InteractiveSurfaceCoverageTests`.
Expected: FAIL because the helper file and audited references do not exist yet.

**Step 3: Write minimal implementation**

Implement:

- `enum AppFullSurfaceTapTargetShape`
- `View.appFullSurfaceTapTarget(_:)`

Use `contentShape(...)` internally for rectangle, rounded rectangle, capsule, and circle.

**Step 4: Run test to verify it passes**

Run the same focused test command.
Expected: PASS

### Task 2: Apply the helper to core CTA surfaces

**Files:**
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/MainView.swift`
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/OnboardingCoachCard.swift`

**Step 1: Write the failing test**

Extend `InteractiveSurfaceCoverageTests` to require helper adoption in the four files above.

**Step 2: Run test to verify it fails**

Run the focused coverage test command.
Expected: FAIL until those files contain explicit helper adoption.

**Step 3: Write minimal implementation**

Apply `appFullSurfaceTapTarget(...)` to:

- auth primary and guest buttons
- auth social buttons where applicable
- main start button
- map floating action buttons and similar rounded CTA surfaces
- onboarding coach card buttons

**Step 4: Run test to verify it passes**

Run the coverage test again.
Expected: PASS

### Task 3: Apply the helper to row and card interaction patterns

**Files:**
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/SidebarNavigation.swift`
- Modify: `StreetStamps/EquipmentView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

Extend `InteractiveSurfaceCoverageTests` to require helper adoption in these files too.

**Step 2: Run test to verify it fails**

Run the focused coverage test command.
Expected: FAIL until those files adopt the helper.

**Step 3: Write minimal implementation**

Apply the helper to:

- profile action buttons and row/button-like sections
- settings segment buttons, toggles, and row cards
- sidebar menu rows
- equipment grid cards and color swatches where the whole visual surface should tap
- friend feed/profile card entry surfaces

**Step 4: Run test to verify it passes**

Run the coverage test again.
Expected: PASS

### Task 4: Run focused verification

**Files:**
- No code changes required

**Step 1: Run source-level tests**

Run:

- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/InteractiveSurfaceCoverageTests`

Expected: PASS if the scheme supports tests.

**Step 2: Run build verification**

Run:

- `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedDataHitTargets build`

Expected: BUILD SUCCEEDED

**Step 3: Manual spot-check**

Verify the key audited interactions now respond across the full visible surface.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-13-button-hit-target-unification-design.md docs/plans/2026-03-13-button-hit-target-unification-implementation.md StreetStamps/AppFullSurfaceTapTarget.swift StreetStamps/AuthEntryView.swift StreetStamps/MainView.swift StreetStamps/MapView.swift StreetStamps/OnboardingCoachCard.swift StreetStamps/ProfileView.swift StreetStamps/SettingsView.swift StreetStamps/SidebarNavigation.swift StreetStamps/EquipmentView.swift StreetStamps/FriendsHubView.swift StreetStampsTests/InteractiveSurfaceCoverageTests.swift
git commit -m "fix: unify full-surface tap targets"
```
