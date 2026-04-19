# Profile Hero Card Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Re-layout the nickname and stats sections on the personal and friend profile screens into shared info/stat cards while preserving scene art, copy, and existing actions.

**Architecture:** Introduce a shared SwiftUI component that renders the info card and two compact stat cards, then wire it into `ProfileView` and `FriendsHubView`. Keep all existing formatting logic and action callbacks on the parent screens so the layout change remains presentation-only.

**Tech Stack:** SwiftUI, XCTest source-parity tests, existing StreetStamps theme helpers

---

### Task 1: Lock the shared layout contract with a failing test

**Files:**
- Modify: `StreetStampsTests/ProfilePostcardSectionSourceParityTests.swift`

**Step 1: Write the failing test**

Add a source-parity test asserting:
- `ProfileView.swift` uses `ProfileHeroInfoStatsSection`
- `FriendsHubView.swift` uses `ProfileHeroInfoStatsSection`
- the shared component file contains the two-card stat API and trailing action slot

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfilePostcardSectionSourceParityTests/test_profileAndFriendHeroesUseSharedInfoStatsCards`

Expected: the new assertion fails, or the run is blocked by the repo's existing unrelated test compile failures before this test executes.

**Step 3: Commit**

Skip until implementation is complete.

### Task 2: Build the shared info/stat card component

**Files:**
- Create: `StreetStamps/ProfileHeroInfoStatsSection.swift`

**Step 1: Write minimal implementation**

Create a reusable component with:
- title/name
- level badge text
- secondary date text
- trailing action slot
- two stat card models rendered side by side

**Step 2: Keep styling aligned with the reference**

Use:
- white cards
- soft icon tiles
- compact spacing
- rounded corners and subtle stroke/shadow consistent with existing profile cards

### Task 3: Wire the personal profile to the shared layout

**Files:**
- Modify: `StreetStamps/ProfileView.swift`

**Step 1: Replace the old name row**

Move the editable display name UI into the shared info card's leading content.

**Step 2: Replace the old embedded stats area**

Render journeys and total distance in the new two-card stat row using current data sources.

**Step 3: Preserve the existing action**

Render the equipment navigation button in the shared trailing action slot.

### Task 4: Wire the friend profile to the shared layout

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Replace the existing name/CTA row**

Move the friend display name, level pill, and joined date into the shared info card.

**Step 2: Replace the old stats presentation**

Render journeys and total distance in the shared two-card stat row using current friend metrics and localization.

**Step 3: Preserve the seat CTA**

Render the existing sit/leave CTA button in the shared trailing action slot with no behavior changes.

### Task 5: Verify and summarize blockers

**Files:**
- Review only

**Step 1: Run targeted verification**

Run:
- `rg -n "ProfileHeroInfoStatsSection" StreetStamps/ProfileView.swift StreetStamps/FriendsHubView.swift StreetStamps/ProfileHeroInfoStatsSection.swift`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfilePostcardSectionSourceParityTests/test_profileAndFriendHeroesUseSharedInfoStatsCards`

**Step 2: Record actual verification status**

If the targeted test still cannot run because the repo has unrelated compile failures, report the exact blocker classes/messages instead of claiming success.
