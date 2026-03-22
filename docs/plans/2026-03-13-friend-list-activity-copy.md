# Friend List Activity Copy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the misleading friend list "Active X ago" copy with a truthful recent-journey subtitle.

**Architecture:** Keep the change in the presentation layer. Extract the friend-list subtitle rules into a small helper that only shows relative time when the friend actually has journey timestamps, then wire the SwiftUI card to render the subtitle conditionally.

**Tech Stack:** Swift, SwiftUI, XCTest, localized `Localizable.strings`

---

### Task 1: Cover the presentation behavior

**Files:**
- Modify: `StreetStampsTests/MapAppearanceSettingsTests.swift`

**Step 1: Write the failing test**

Add tests asserting that the friend-list subtitle:
- uses a "recent journey" label when a journey timestamp exists
- returns `nil` when the friend has no journeys

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendListPresencePresentationTests`

Expected: FAIL because the presentation helper does not exist yet.

### Task 2: Implement the truthful subtitle logic

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Add minimal implementation**

Implement a helper that:
- finds the latest journey timestamp from `endTime` or `startTime`
- formats a localized short relative string
- returns `nil` when no journey exists

**Step 2: Update the card**

Render the subtitle only when the helper returns a value, instead of always showing activity text.

**Step 3: Run the focused test**

Run the same `xcodebuild test ... -only-testing:StreetStampsTests/FriendListPresencePresentationTests` command.

Expected: PASS.

### Task 3: Update localized copy

**Files:**
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hant.lproj/Localizable.strings`
- Modify: `StreetStamps/es.lproj/Localizable.strings`
- Modify: `StreetStamps/fr.lproj/Localizable.strings`
- Modify: `StreetStamps/ja.lproj/Localizable.strings`
- Modify: `StreetStamps/ko.lproj/Localizable.strings`

**Step 1: Add a new localized key**

Introduce `friends_recent_journey_ago` so the UI no longer claims general activity.

**Step 2: Verify localization coverage**

Run the focused friend copy/localization tests if needed after the code test is green.

