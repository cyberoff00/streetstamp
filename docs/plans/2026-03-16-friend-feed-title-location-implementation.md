# Friend Feed Title And Location Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update friend feed cards so city locations always come from `cityID`, while `journey` and `memory` event titles prefer a real custom journey title before falling back to generic event copy.

**Architecture:** Keep city unlock detection untouched and isolate the behavior change inside `FriendFeedLogic` plus the feed event builder in `FriendsHubView.swift`. This lets the feed title and location rules become independently testable without changing the friend feed data model.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcodebuild

---

### Task 1: Lock the desired feed copy in tests

**Files:**
- Modify: `StreetStampsTests/MapAppearanceSettingsTests.swift`

**Step 1: Write the failing test**

Add tests that assert:
- `journey` events use `发布了旅程「XXXX」` when the title differs from the resolved city name.
- `memory` events use the same override when the title differs from the resolved city name.
- generic copy remains when the journey title is just the city name.
- unresolved city names produce an empty location string.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendFeedLogicTests`

Expected: FAIL because `FriendFeedLogic` still returns the old generic title and still treats the location fallback too loosely.

### Task 2: Implement minimal friend-feed logic changes

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hant.lproj/Localizable.strings`
- Modify: `StreetStamps/ja.lproj/Localizable.strings`
- Modify: `StreetStamps/ko.lproj/Localizable.strings`
- Modify: `StreetStamps/es.lproj/Localizable.strings`
- Modify: `StreetStamps/fr.lproj/Localizable.strings`

**Step 1: Write minimal implementation**

- Add a helper in `FriendFeedLogic` that detects whether a journey title is truly custom relative to the resolved city name.
- Update `eventTitle(...)` so only `journey` and `memory` events can emit `friends_event_published_journey`.
- Update the feed event builder to pass a city-only location string and hide the line when city resolution fails.
- Add the new localized string key across the supported localization files.

**Step 2: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendFeedLogicTests`

Expected: PASS

### Task 3: Run a focused build sanity check

**Files:**
- No source changes expected

**Step 1: Run build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedDataCodex`

Expected: build reaches completion without new friend-feed compile errors.
