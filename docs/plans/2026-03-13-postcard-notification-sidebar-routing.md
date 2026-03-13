# Postcard Notification Sidebar Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make tapping a postcard notification open the existing sidebar postcard page immediately, without waiting for the notification UI to dismiss first.

**Architecture:** Add an app-level postcard sidebar route to `AppFlowCoordinator`, have `MainTabView` consume that route to present the sidebar postcard sheet, and route notification taps plus postcard deep links through that same path. Keep `PostcardInboxView` unchanged except for receiving the existing initial box and focus message intent through the sidebar entry view.

**Tech Stack:** SwiftUI, Combine, XCTest, `UNUserNotificationCenterDelegate`

---

### Task 1: Document the approved routing change

**Files:**
- Create: `docs/plans/2026-03-13-postcard-notification-sidebar-design.md`
- Create: `docs/plans/2026-03-13-postcard-notification-sidebar-routing.md`

**Step 1: Save the approved design**

Write the short design doc describing the current notification timing problem, the new app-level sidebar route, and the expected postcard page behavior.

**Step 2: Save the implementation plan**

Write this plan with exact files, TDD order, and validation commands.

**Step 3: Commit**

```bash
git add docs/plans/2026-03-13-postcard-notification-sidebar-design.md docs/plans/2026-03-13-postcard-notification-sidebar-routing.md
git commit -m "docs: add postcard notification sidebar routing plan"
```

### Task 2: Add failing route tests

**Files:**
- Modify: `StreetStampsTests/AppDeepLinkStoreTests.swift`
- Create: `StreetStampsTests/AppFlowCoordinatorTests.swift`

**Step 1: Write the failing tests**

Add tests that verify:
- postcard deep links parse into a received inbox intent with `messageID`
- `AppFlowCoordinator` stores a pending postcard sidebar intent and increments a delivery signal
- consuming the pending postcard sidebar intent clears the stored value

**Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AppDeepLinkStoreTests -only-testing:StreetStampsTests/AppFlowCoordinatorTests
```

Expected: FAIL because the postcard parser helper and app-level postcard sidebar route do not exist yet.

**Step 3: Commit**

```bash
git add StreetStampsTests/AppDeepLinkStoreTests.swift StreetStampsTests/AppFlowCoordinatorTests.swift
git commit -m "test: cover postcard sidebar routing"
```

### Task 3: Implement app-level postcard sidebar routing

**Files:**
- Modify: `StreetStamps/AppFlowCoordinator.swift`
- Modify: `StreetStamps/MainTab.swift`
- Modify: `StreetStamps/PostcardNotificationBridge.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`

**Step 1: Add the route state**

Add a postcard sidebar delivery signal plus pending `PostcardInboxIntent` storage to `AppFlowCoordinator`, along with request and consume helpers.

**Step 2: Reuse postcard parsing without `onOpenURL` dependency**

Expose postcard deep-link parsing in a testable way so both app URL handling and notification taps can resolve a `PostcardInboxIntent`.

**Step 3: Present the sidebar postcard sheet from the main tab shell**

Update `MainTabView` to observe the postcard sidebar signal, store the latest intent locally for the sheet presentation, and open `.postcards` with the appropriate box/message focus.

**Step 4: Route notification taps directly**

Change `AppNotificationDelegate` so a postcard notification tap requests the postcard sidebar route directly on `AppFlowCoordinator` instead of calling `UIApplication.shared.open(url)`.

**Step 5: Route postcard deep links through the same path**

Update `StreetStampsApp` so postcard deep links also request the postcard sidebar route, while password reset and invite links keep their current behavior.

**Step 6: Commit**

```bash
git add StreetStamps/AppFlowCoordinator.swift StreetStamps/MainTab.swift StreetStamps/PostcardNotificationBridge.swift StreetStamps/StreetStampsApp.swift
git commit -m "fix: open postcard sidebar from notification taps"
```

### Task 4: Verify the fix

**Files:**
- Test: `StreetStampsTests/AppDeepLinkStoreTests.swift`
- Test: `StreetStampsTests/AppFlowCoordinatorTests.swift`

**Step 1: Run focused tests**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/AppDeepLinkStoreTests -only-testing:StreetStampsTests/AppFlowCoordinatorTests
```

Expected: PASS

**Step 2: Run one broader safety check**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests -only-testing:StreetStampsTests/NavigationChromePolicyTests
```

Expected: PASS

**Step 3: Summarize verification**

Capture the commands run and the observed pass/fail status before claiming the fix is complete.
