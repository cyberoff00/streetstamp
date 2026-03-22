# Lifelog Step Modal Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Tighten the Lifelog step milestone popup so it feels cleaner and less visually awkward.

**Architecture:** Keep the existing modal behavior and interaction model, but move the layout tuning into `LifelogStepMilestonePresentation` so copy and spacing decisions are explicit and testable. Update the SwiftUI modal to use a more compact header stack with the close button overlaid instead of reserving a full row.

**Tech Stack:** SwiftUI, XCTest

---

### Task 1: Lock the new presentation rules with tests

**Files:**
- Modify: `StreetStampsTests/LifelogStepMilestonePresentationTests.swift`
- Test: `StreetStampsTests/LifelogStepMilestonePresentationTests.swift`

**Step 1: Write the failing test**

Add assertions for the refreshed presentation rules:
- the celebration headline is hidden
- the compact top spacing value is applied

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/LifelogStepMilestonePresentationTests`

Expected: FAIL because the new presentation properties do not exist yet.

**Step 3: Write minimal implementation**

Add the new presentation constants in `StreetStamps/LifelogView.swift` and consume them in the modal layout.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the presentation test target passes.

### Task 2: Refresh the modal layout

**Files:**
- Modify: `StreetStamps/LifelogView.swift`

**Step 1: Update the header layout**

Move the close button into an overlay-aligned top trailing control so it no longer burns a full header row.

**Step 2: Tighten the hero block**

Reduce the icon circle size, shrink the spacing around the hero block, and reduce container padding at the top.

**Step 3: Remove the noisy celebration line**

Hide the extra celebratory copy and keep the title, step count, and supporting sentence as the only content.

**Step 4: Verify visually through code review**

Re-read the updated structure in `StreetStamps/LifelogView.swift` and confirm the hierarchy matches the approved compact-card design.
