# Lifelog Localization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Localize the Lifelog title as English `LIFELOG` and Simplified Chinese `足迹`, and replace a small set of formal user-facing hardcoded strings with localized keys.

**Architecture:** Reuse the existing `L10n.t(...)` helper and `Localizable.strings` files. Extend the localization coverage test to assert the specific Lifelog title values, then add the missing keys and swap hardcoded SwiftUI strings in formal user-facing screens to localized lookups.

**Tech Stack:** Swift, SwiftUI, XCTest, `Localizable.strings`

---

### Task 1: Lock the Lifelog title behavior with a test

**Files:**
- Modify: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Write the failing test**

Add a test that loads English and Simplified Chinese `Localizable.strings` and asserts:
- `tab_lifelog == "LIFELOG"` in English
- `lifelog_title == "LIFELOG"` in English
- `tab_lifelog == "足迹"` in Simplified Chinese
- `lifelog_title == "足迹"` in Simplified Chinese

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`

Expected: FAIL because the current English strings still use `Lifelog`.

**Step 3: Write minimal implementation**

Update the relevant values in `StreetStamps/en.lproj/Localizable.strings` and `StreetStamps/zh-Hans.lproj/Localizable.strings`.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

### Task 2: Localize formal hardcoded user-facing copy

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/AppSplashView.swift`
- Modify: `StreetStamps/IntroSlidesView.swift`
- Modify: `StreetStamps/FlippablePostcardView.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`

**Step 1: Add missing localization keys**

Add keys for:
- Private transfer explanatory copy and scanner guidance
- Friends notifications loading / empty / title / mark-all-read
- Password reset prompt line
- Splash tagline
- Intro skip
- Postcard label text

**Step 2: Replace hardcoded view strings**

Swap the hardcoded `Text(...)`, `NavigationChrome(title: ...)`, and accessibility label strings in the files above to `L10n.t(...)`.

**Step 3: Run focused tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests -only-testing:StreetStampsTests/SettingsRowPresentationTests`

Expected: PASS.
