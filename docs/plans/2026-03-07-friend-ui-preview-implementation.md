# Friend UI Preview Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Settings-based local friend profile preview screen for testing the friend UI and seated sofa state without backend data.

**Architecture:** Add a standalone preview view and a tiny local mock-data helper under `StreetStamps/`, then link it from the existing `DEBUG TOOLS` section in Settings. Keep all preview behavior local to the page so no real friend navigation, backend calls, or shared social state are touched.

**Tech Stack:** SwiftUI, XCTest, existing `FriendProfileSnapshot` and `SofaProfileSceneView`

---

### Task 1: Lock Preview Data Behavior

**Files:**
- Create: `StreetStampsTests/DebugFriendProfilePreviewTests.swift`
- Test: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Write the failing test**

Write a unit test that expects the preview helper to provide:

- A non-empty mock friend profile
- At least one journey and one city/stat value
- A seated scene state that places the visitor on the right and disables the CTA

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/DebugFriendProfilePreviewTests`

Expected: FAIL because the preview helper does not exist yet.

**Step 3: Write minimal implementation**

Create the local preview helper with deterministic mock data and a scene-state helper.

**Step 4: Run test to verify it passes**

Run the same test command and confirm PASS.

### Task 2: Add Settings Entry And Preview Screen

**Files:**
- Create: `StreetStamps/DebugFriendProfilePreviewView.swift`
- Modify: `StreetStamps/SettingsView.swift`

**Step 1: Write the failing test**

Reuse the Task 1 helper coverage as the contract for the UI inputs. Do not add SwiftUI snapshot complexity.

**Step 2: Run test to verify it fails**

Covered by Task 1 red phase.

**Step 3: Write minimal implementation**

- Add a `FRIEND UI PREVIEW` navigation row under `DEBUG TOOLS`
- Build the preview page with:
  - Local mock friend profile
  - `SofaProfileSceneView`
  - A segmented seated/unseated switch
  - A local CTA button that sets seated state
  - Static feature cards for visual validation only

**Step 4: Run test to verify it passes**

Run:

- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/DebugFriendProfilePreviewTests`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests`
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: tests pass and build succeeds.
