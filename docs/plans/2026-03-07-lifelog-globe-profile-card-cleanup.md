# Lifelog Globe Profile Card Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the shared profile summary cards in Lifelog and Globe View, and remove the extra divider spacing above the Lifelog calendar toggle.

**Architecture:** Extract the card text formatting into a small pure helper so the visible copy can be regression-tested. Update both SwiftUI screens to use the helper, remove the level progress row and bar, and tighten the Lifelog dock layout by deleting the divider between the card and the calendar panel.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Add regression coverage for simplified profile card copy

**Files:**
- Create: `StreetStamps/ProfileSummaryCardContent.swift`
- Create: `StreetStampsTests/ProfileSummaryCardContentTests.swift`

**Step 1: Write the failing test**

Add tests that expect:
- the level subtitle to render only `Lv.x`
- the stats subtitle to render only `X Cities  X Memories`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSummaryCardContentTests`

Expected: FAIL because the helper does not exist yet.

**Step 3: Write minimal implementation**

Implement a small helper that formats the two visible text rows for the profile summary card.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new tests pass.

### Task 2: Apply the UI cleanup to Lifelog and Globe View

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/GlobeViewScreen.swift`

**Step 1: Update the profile cards**

Replace the current level-progress row, progress bar, and long stats copy with the helper-backed two-line layout.

**Step 2: Remove the extra divider and rebalance spacing**

Delete the divider between the Lifelog profile card and calendar panel so the `Display by month` / `Display by day` row sits with balanced vertical spacing.

**Step 3: Run targeted verification**

Run the focused test suite and a simulator build for the main app target.
