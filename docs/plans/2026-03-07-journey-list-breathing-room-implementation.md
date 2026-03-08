# Journey List Breathing Room Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the journey list so cards have more breathing room, thumbnails use a muted map treatment, and every thumbnail frames the full route instead of a cropped segment.

**Architecture:** Extract thumbnail framing into a small pure helper that computes a region from route coordinates and target aspect ratio. Use that helper from the journey snapshot renderer, post-process the snapshot base image for a muted look, and adjust the SwiftUI list/card layout to increase separation and preserve the full thumbnail frame.

**Tech Stack:** SwiftUI, MapKit, Core Image, XCTest

---

### Task 1: Add route thumbnail framing tests

**Files:**
- Create: `StreetStampsTests/JourneySnapshotFramingTests.swift`
- Modify: `StreetStamps/CityMapUtils.swift`

**Step 1: Write the failing test**

Add tests that verify:
- all route coordinates fit inside the computed region
- the helper does not add excessive padding beyond what the target aspect ratio requires

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneySnapshotFramingTests`

Expected: FAIL because the framing helper does not exist yet.

**Step 3: Write minimal implementation**

Implement a helper that:
- maps route coordinates to MapKit coordinates
- computes bounds for the full route
- applies a small route padding factor
- expands one axis only as needed to match the snapshot aspect ratio

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS

### Task 2: Update journey thumbnail rendering

**Files:**
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/CityMapUtils.swift`

**Step 1: Replace city-focused thumbnail framing**

Use the new framing helper in the journey snapshot renderer so the entire route is visible in the snapshot.

**Step 2: Mute the base map**

Apply a light darkening and desaturation pass to the snapshot image before drawing the route overlay.

**Step 3: Preserve the full thumbnail image in the card**

Update the SwiftUI thumbnail view to display the snapshot without cropping.

**Step 4: Run focused verification**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneySnapshotFramingTests`

Expected: PASS

### Task 3: Increase list/card breathing room

**Files:**
- Modify: `StreetStamps/MyJourneysView.swift`

**Step 1: Increase list spacing and padding**

Raise vertical spacing between cards and slightly widen outer insets.

**Step 2: Relax card internals**

Increase the spacing and padding around card content so each journey reads more independently.

**Step 3: Run regression verification**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneySnapshotFramingTests`

Expected: PASS
