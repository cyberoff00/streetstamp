# Save Journey Friends Visibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enforce friends-visibility save rules and add overall-memory photo attachments in the save-journey flow.

**Architecture:** Keep validation in a small policy layer so the save sheet and journey list can share the same rule set. Extend `JourneyRoute` with persisted overall-memory photo paths and let the save sheet reuse the existing camera/library pickers and thumbnail component used by memory editing.

**Tech Stack:** SwiftUI, XCTest, existing UIKit-based image pickers, Codable models

---

### Task 1: Visibility policy

**Files:**
- Modify: `StreetStamps/JourneyVisibility.swift`
- Test: `StreetStampsTests/JourneyVisibilityPolicyTests.swift`

**Step 1: Write the failing test**

- Add tests for:
  - guest user switching to `friendsOnly` returns a denied result with a login reason
  - logged-in user switching to `friendsOnly` for a sub-2km journey with no memories returns a denied result with an eligibility reason
  - logged-in user switching to `friendsOnly` for a 2km journey or a journey with memories is allowed

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyVisibilityPolicyTests`

Expected: FAIL because the richer policy API and reason handling do not exist yet.

**Step 3: Write minimal implementation**

- Replace the bare boolean policy with a structured decision containing:
  - `isAllowed`
  - denial reason enum
- Accept journey distance and memory count as inputs.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm green.

### Task 2: Persist overall-memory photos

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/JourneyRouteCodableTests.swift`

**Step 1: Write the failing test**

- Add a Codable round-trip test proving `overallMemoryImagePaths` survives encode/decode.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyRouteCodableTests`

Expected: FAIL because `JourneyRoute` has no such field yet.

**Step 3: Write minimal implementation**

- Add `overallMemoryImagePaths` to `JourneyRoute`
- Update init, coding keys, decode, encode, and merge behavior

**Step 4: Run test to verify it passes**

Run the same targeted test command and confirm green.

### Task 3: Save sheet wiring

**Files:**
- Modify: `StreetStamps/SharingCard.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/*/*.strings`
- Test: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Write the failing test**

- Add localization keys to the coverage list for the new visibility-denial messages and overall-memory photo label if needed.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`

Expected: FAIL until the new keys are added everywhere.

**Step 3: Write minimal implementation**

- In `PopSharingCard`, intercept visibility changes, evaluate the policy, revert invalid changes, and show an alert with the reason.
- Reuse the camera/library pickers and thumbnails for overall-memory attachments with a 3-photo cap.
- Increase the save button width.
- Update `MyJourneysView` to use the same policy result so list-level visibility changes stay consistent.
- Add localized strings in all supported languages.

**Step 4: Run test to verify it passes**

Run the localization test and then a focused build/test pass for the touched suites.
