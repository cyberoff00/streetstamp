# Onboarding Screenshot Slides Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the existing icon-based intro slides with a four-page onboarding flow that supports localized copy and paired screenshot layouts.

**Architecture:** Keep the existing first-launch gate in `StreetStampsApp` unchanged and swap only the presentation inside `IntroSlidesView`. Model each slide with localization keys plus two screenshot asset names so the UI can render real screenshots when assets exist and a safe placeholder when they do not.

**Tech Stack:** SwiftUI, `Localizable.strings`, XCTest

---

### Task 1: Add localized onboarding copy

**Files:**
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Test: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Write the failing test**

Add assertions for the new onboarding title/subtitle/button keys in English and Simplified Chinese.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`
Expected: FAIL because the new localization keys do not exist yet.

**Step 3: Write minimal implementation**

Add the new keys to English and Simplified Chinese string tables. Keep English as placeholder-ready copy for the later English screenshot variant.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS for `LocalizationCoverageTests`.

### Task 2: Replace icon slides with paired screenshot cards

**Files:**
- Modify: `StreetStamps/IntroSlidesView.swift`

**Step 1: Write the failing test**

Use Task 1 as the safety net and rely on compile/build verification for this SwiftUI-only layout change.

**Step 2: Run test to verify it fails**

Not applicable beyond the localization red step; this task is verified by build plus UI inspection.

**Step 3: Write minimal implementation**

Rebuild `IntroSlidesView` to:
- define four slides with localization keys and two screenshot asset names each
- render a stacked phone-card layout matching the provided direction
- preserve skip, pagination, and finish behavior
- show a clear placeholder card if a screenshot asset is missing so the app still builds before assets are added

**Step 4: Run build verification**

Run: `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: BUILD SUCCEEDED.

### Task 3: Final verification

**Files:**
- Review: `StreetStamps/IntroSlidesView.swift`
- Review: `StreetStamps/en.lproj/Localizable.strings`
- Review: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Review: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Run focused verification**

Run:
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`
- `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

**Step 2: Inspect result**

Confirm the localization test passes and the app builds with the new onboarding view.
