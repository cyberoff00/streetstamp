# Equipment Category Scroll Hint Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the equipment category strip more obviously horizontally scrollable so users notice there are more equipment categories off-screen.

**Architecture:** Keep the existing horizontal category `ScrollView`, but add two low-friction affordances inside `EquipmentView`: trailing peek/extra padding so content feels clipped rather than complete, and a right-edge visual hint that fades over the scroll container. Verify the behavior with a source-coverage regression test to keep the cue from being removed accidentally.

**Tech Stack:** SwiftUI, XCTest source-coverage tests

---

### Task 1: Lock in the new affordance with a failing regression test

**Files:**
- Modify: `StreetStampsTests/InteractiveSurfaceCoverageTests.swift`
- Test: `StreetStampsTests/InteractiveSurfaceCoverageTests.swift`

**Step 1: Write the failing test**

Add a test that asserts `EquipmentView.swift` contains both a named trailing affordance helper and a named scroll hint overlay.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/InteractiveSurfaceCoverageTests/test_equipmentCategoryRowIncludesHorizontalScrollAffordance`

Expected: FAIL because the helper/overlay identifiers do not exist yet.

**Step 3: Write minimal implementation**

Add a small trailing spacer/peek to the horizontal category row and overlay a right-edge fade plus chevron hint that disappears into the card edge.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and expect PASS.

### Task 2: Implement the category strip cues

**Files:**
- Modify: `StreetStamps/EquipmentView.swift`

**Step 1: Add named layout constants/helpers**

Introduce small constants/helpers for the category row trailing peek and scroll hint overlay so the intent is explicit and easy to test.

**Step 2: Update the horizontal category row**

Keep the current category buttons, but add trailing inset/spacer so the first screen does not look "finished" when there are more categories off-screen.

**Step 3: Add a right-edge visual hint**

Overlay a subtle gradient fade and chevron on the right edge of the category container to suggest more content continues horizontally.

**Step 4: Keep styling consistent**

Match the existing card colors, border language, and compact sizing so the cue feels native to the current screen rather than like a tutorial banner.

### Task 3: Verify

**Files:**
- Test: `StreetStampsTests/InteractiveSurfaceCoverageTests.swift`

**Step 1: Run focused regression coverage**

Run the focused `xcodebuild test` command for the new test.

**Step 2: Run the full source-coverage test file**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/InteractiveSurfaceCoverageTests`

Expected: PASS.
