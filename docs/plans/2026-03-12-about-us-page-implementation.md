# About Us Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the placeholder About Us action in Settings with a real reading page styled like Journey Memory and populated with the provided Chinese copy unchanged.

**Architecture:** Add a small presentation model that owns the static About Us content and section breaks, then build a dedicated SwiftUI screen that renders that content with existing Figma/UI theme primitives. Update the Settings information section to navigate to the new screen instead of showing the placeholder alert.

**Tech Stack:** Swift, SwiftUI, XCTest, existing `FigmaTheme` / `figmaSurfaceCard` styling helpers.

---

### Task 1: Define About Us presentation content

**Files:**
- Create: `StreetStamps/AboutUsView.swift`
- Test: `StreetStampsTests/AboutUsPresentationTests.swift`

**Step 1: Write the failing test**

Create tests that assert:
- the page title is `关于我们`
- the location line is `伦敦`
- the section list preserves the provided headings and paragraph counts

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AboutUsPresentationTests`
Expected: FAIL because the presentation type does not exist yet.

**Step 3: Write minimal implementation**

Add a presentation model with static strings and section arrays containing the original copy without rewriting.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new tests pass.

**Step 5: Commit**

```bash
git add StreetStamps/AboutUsView.swift StreetStampsTests/AboutUsPresentationTests.swift docs/plans/2026-03-12-about-us-page-implementation.md
git commit -m "feat: add about us page"
```

### Task 2: Build the About Us screen and navigation

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Create: `StreetStamps/AboutUsView.swift`

**Step 1: Wire the settings entry**

Replace the current placeholder button in the information section with a `NavigationLink` to the new screen.

**Step 2: Build the SwiftUI layout**

Render:
- navigation header with back
- Journey Memory-like hero card
- section cards containing the unchanged Chinese copy

**Step 3: Keep styling constrained**

Reuse existing theme helpers instead of introducing new global style abstractions.

**Step 4: Manual review**

Check the copy order, spacing, and that the headings use only text already present in the source content.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsView.swift StreetStamps/AboutUsView.swift
git commit -m "feat: connect settings about us page"
```

### Task 3: Verify the finished change

**Files:**
- Modify: `StreetStamps/AboutUsView.swift`
- Modify: `StreetStamps/SettingsView.swift`
- Test: `StreetStampsTests/AboutUsPresentationTests.swift`

**Step 1: Run the targeted tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AboutUsPresentationTests -only-testing:StreetStampsTests/LocalizationCoverageTests`

**Step 2: Inspect the diff**

Run: `git diff -- StreetStamps/AboutUsView.swift StreetStamps/SettingsView.swift StreetStampsTests/AboutUsPresentationTests.swift`

**Step 3: Report actual status**

Only claim completion if the test command exits successfully and the diff matches the intended scope.
