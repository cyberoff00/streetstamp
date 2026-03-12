# Live Activity Unified UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the mode-specific Live Activity UI with one shared avatar-led design and route the fixed action button into the active tracking screen's direct camera capture flow.

**Architecture:** Keep the existing ActivityKit attribute model intact, but refactor widget rendering to a single shared lock-screen and Dynamic Island presentation. Add a dedicated widget capture intent and a distinct app-side notification path so the app can return to the active tracking screen and present camera capture directly without going through the add-memory editor.

**Tech Stack:** SwiftUI, WidgetKit, ActivityKit, AppIntents, Combine, XCTest, existing app flow coordination

---

### Task 1: Lock The Widget Capture Action Contract

**Files:**
- Modify: `StreetStamps/LiveActivityManager.swift`
- Create: `StreetStampsTests/LiveActivityManagerWidgetActionTests.swift`

**Step 1: Write the failing test**

Add a unit test that exercises widget-action consumption from App Group defaults and expects:

- a new capture flag key is detected
- the flag is cleared after handling
- the manager posts a dedicated `.openCaptureFromWidget` notification

Use NotificationCenter observation rather than UI assertions.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveActivityManagerWidgetActionTests`

Expected: FAIL because the capture flag and notification path do not exist yet.

**Step 3: Write minimal implementation**

In `StreetStamps/LiveActivityManager.swift`:

- add a new App Group boolean key such as `pendingOpenCapture`
- extend `checkPendingWidgetActions()` to consume that key
- post `Notification.Name.openCaptureFromWidget`
- keep existing add-memory and toggle-pause handling unchanged unless the capture path supersedes add-memory for the widget

**Step 4: Run test to verify it passes**

Run the same test command and confirm PASS.

### Task 2: Add A Dedicated Live Activity Capture Intent

**Files:**
- Modify: `TrackingWidge/StreetStampsWidgets/AddMemoryIntent.swift`
- Modify: `TrackingWidge/StreetStampsWidgets/README.md`

**Step 1: Write the failing test**

No separate widget-unit test is required if the app-side red test from Task 1 proves the new contract. Treat the missing capture intent type and key write as the implementation gap.

**Step 2: Run test to verify it fails**

Covered by Task 1 red phase plus an app/widget build failure if the new intent is referenced before implementation.

**Step 3: Write minimal implementation**

In the widget intent file:

- add a dedicated intent such as `OpenCaptureIntent`
- set `openAppWhenRun = true`
- write `pendingOpenCapture = true` into the shared App Group defaults
- keep `AddMemoryIntent` only if still used elsewhere; otherwise rename or retire it carefully

Update the README to describe the new unified action behavior instead of daily-mode add-memory behavior.

**Step 4: Run test to verify it passes**

Run:

- `xcodebuild build -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveActivityManagerWidgetActionTests`

Expected: widget extension builds and the app-side test passes.

### Task 3: Refactor The Tracking Screen To Open Camera Directly

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/TrackTileBuilderTests.swift`

**Step 1: Write the failing test**

Add a focused test around the extracted routing helper or notification-handling policy that expects widget-triggered capture to request direct camera presentation instead of memory-editor presentation.

If `MapView` is too UI-heavy for direct unit testing, first extract a tiny testable policy/helper that decides:

- whether widget capture is allowed while tracking
- whether the outcome is `.openCamera` or `.ignore`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/TrackTileBuilderTests`

Expected: FAIL because the extracted helper or direct-camera behavior does not exist yet.

**Step 3: Write minimal implementation**

In `StreetStamps/MapView.swift`:

- add a listener for `.openCaptureFromWidget`
- require an active track according to current capture rules
- set `editingMemory = nil`
- set `showMemoryEditor = false` if needed
- set `showCamera = true`

Do not route through the memory editor first.

**Step 4: Run test to verify it passes**

Run the same targeted test command and confirm PASS.

### Task 4: Route Widget Capture Back To The Active Tracking Screen

**Files:**
- Modify: `StreetStamps/AppFlowCoordinator.swift`
- Modify: `StreetStamps/MainTab.swift`
- Modify: `StreetStamps/LiveActivityManager.swift`
- Create: `StreetStampsTests/AppFlowCoordinatorWidgetCaptureTests.swift`

**Step 1: Write the failing test**

Add a unit test that expects the app flow coordinator to support a widget-triggered capture request by:

- switching to the start/tracking tab
- requesting resume of the ongoing journey when appropriate
- exposing a one-shot capture request signal the tracking screen can consume after navigation settles

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AppFlowCoordinatorWidgetCaptureTests`

Expected: FAIL because no widget-capture routing API exists in the flow coordinator.

**Step 3: Write minimal implementation**

Add the smallest coordinator surface needed to:

- request the start tab
- request resume of the ongoing journey
- hold a pending capture trigger until the map screen becomes active

Then wire `MainTabView` and the tracking screen to consume and clear that trigger safely.

**Step 4: Run test to verify it passes**

Run the same targeted test command and confirm PASS.

### Task 5: Replace Mode-Specific Live Activity Views With One Shared Card

**Files:**
- Modify: `TrackingWidge/StreetStampsWidgets/TrackingLiveActivity.swift`
- Modify: `TrackingWidge/StreetStampsWidgets/Assets.xcassets/Contents.json`
- Create or Modify: widget avatar assets as needed under `TrackingWidge/StreetStampsWidgets/Assets.xcassets/`

**Step 1: Write the failing test**

Add a lightweight rendering contract test if practical for formatting helpers or extracted view-model helpers, for example:

- shared formatter returns distance and duration regardless of mode
- no view-model branch emits mode-specific labels

If view testing is too expensive, use build validation as the red/green guard and keep the logic extraction narrowly testable.

**Step 2: Run test to verify it fails**

Run:

- `xcodebuild build -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: either FAIL once shared helpers are referenced before implementation, or visual contract remains unmet until implementation is complete.

**Step 3: Write minimal implementation**

In `TrackingLiveActivity.swift`:

- remove `SportModeLockScreen` and `DailyModeLockScreen`
- introduce one shared lock-screen view
- introduce one shared Dynamic Island layout
- keep distance and duration visible together
- replace the mode-driven bottom button with the fixed capture intent button
- add the avatar tile on the left using widget-safe assets

Keep formatting helpers shared and mode-agnostic.

**Step 4: Run test to verify it passes**

Run:

- `xcodebuild build -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: widget extension builds cleanly.

### Task 6: Verify End-To-End Behavior

**Files:**
- Modify: `docs/plans/2026-03-12-live-activity-unified-ui-design.md`
- Modify: `docs/plans/2026-03-12-live-activity-unified-ui-implementation.md`

**Step 1: Run targeted tests**

Run:

- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveActivityManagerWidgetActionTests`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AppFlowCoordinatorWidgetCaptureTests`

Expected: PASS.

**Step 2: Run app and widget builds**

Run:

- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
- `xcodebuild build -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: both targets build successfully.

**Step 3: Manual verification**

Verify on simulator or device:

- start tracking
- confirm the Live Activity lock screen card uses the unified avatar/stat/button layout
- confirm Dynamic Island no longer shows sport/daily-specific presentation
- switch to a different tab or deeper page
- tap the Live Activity button
- confirm the app returns to the active tracking screen and opens the system camera directly

**Step 4: Document any visual or sequencing adjustments**

If manual verification requires minor spacing or launch-timing fixes, record them in the design/implementation docs before final signoff.
