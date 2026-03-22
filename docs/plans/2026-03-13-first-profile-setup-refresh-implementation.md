# First Profile Setup Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the first profile setup screen into a compact single-screen flow and ensure its visible buttons use full-surface tap targets.

**Architecture:** Add a small presentation/config contract that describes the approved minimal copy and hidden sections, then update `FirstProfileSetupView` to render from that contract with a fixed vertical layout. Fix button hit targets by moving shape/layout modifiers into button labels and applying explicit content shapes.

**Tech Stack:** SwiftUI, XCTest, localized `.strings` resources

---

### Task 1: Lock the approved simplified presentation in tests

**Files:**
- Create: `StreetStampsTests/FirstProfileSetupViewModelTests.swift`
- Modify: `StreetStamps/FirstProfileSetupView.swift`

**Step 1: Write the failing test**

Add a test that asserts the setup presentation contract:

- hero title is `profile_setup_avatar_title`
- hero helper is `profile_setup_avatar_hint`
- subtitle is hidden
- nickname helper is hidden
- summary card is hidden

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FirstProfileSetupViewModelTests`
Expected: FAIL because the presentation contract does not exist yet

**Step 3: Write minimal implementation**

Add a small presentation/config type in `FirstProfileSetupView.swift` with the minimal properties required by the test.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command
Expected: PASS

### Task 2: Lock button hit-area policy in tests

**Files:**
- Modify: `StreetStampsTests/FirstProfileSetupViewModelTests.swift`
- Modify: `StreetStamps/FirstProfileSetupView.swift`

**Step 1: Write the failing test**

Add a test that asserts setup primary actions declare full-surface hit targeting through a small testable contract, for example `usesFullSurfaceHitTarget == true`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FirstProfileSetupViewModelTests`
Expected: FAIL because the hit-target contract is missing or false

**Step 3: Write minimal implementation**

Extend the presentation/helper contract so setup actions expose the full-surface hit-target requirement.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command
Expected: PASS

### Task 3: Implement the simplified setup layout

**Files:**
- Modify: `StreetStamps/FirstProfileSetupView.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hant.lproj/Localizable.strings`
- Modify: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Write the failing test**

Add a localization test that asserts the new avatar title/helper copy in English and Simplified Chinese.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`
Expected: FAIL because the localized values still contain the old copy

**Step 3: Write minimal implementation**

Update the setup view to:

- remove the outer `ScrollView`
- hide the subtitle
- show the approved avatar title/helper copy
- hide nickname helper and summary card
- tighten spacing so the page fits on one screen

Update localized strings to match the new copy.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command
Expected: PASS

### Task 4: Fix setup button hit areas and verify

**Files:**
- Modify: `StreetStamps/FirstProfileSetupView.swift`
- Test: manual simulator verification

**Step 1: Write the failing test**

Use the hit-target policy test from Task 2 as the failing contract before implementation.

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `FirstProfileSetupViewModelTests`
Expected: FAIL until the setup actions opt into full-surface hit targets

**Step 3: Write minimal implementation**

For the setup screen buttons:

- wrap visible content inside the `Button` label
- move sizing/background/clip/overlay modifiers onto the label
- add `.contentShape(...)` matching the rendered shape

**Step 4: Run test to verify it passes**

Run the focused `xcodebuild test` command again
Expected: PASS

### Task 5: Run focused verification

**Files:**
- No code changes required

**Step 1: Run tests**

Run:

- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FirstProfileSetupViewModelTests`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`

Expected: PASS

**Step 2: Manual spot-check**

Verify in simulator that:

- the screen no longer scrolls
- `跳过` remains the only top-right action
- the avatar title/helper use the approved copy
- visible setup buttons respond across the full drawn surface

**Step 3: Commit**

```bash
git add docs/plans/2026-03-13-first-profile-setup-refresh-design.md docs/plans/2026-03-13-first-profile-setup-refresh-implementation.md StreetStamps/FirstProfileSetupView.swift StreetStamps/en.lproj/Localizable.strings StreetStamps/zh-Hans.lproj/Localizable.strings StreetStamps/zh-Hant.lproj/Localizable.strings StreetStampsTests/FirstProfileSetupViewModelTests.swift StreetStampsTests/LocalizationCoverageTests.swift
git commit -m "refactor: simplify first profile setup screen"
```
