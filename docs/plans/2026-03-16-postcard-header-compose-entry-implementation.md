# Postcard Header Compose Entry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a postcard compose button to the sent-box header and let that entry open the existing 1:1 postcard composer in an initially empty-recipient state.

**Architecture:** Keep postcard sending strictly 1:1. Refactor the composer to support two launch modes: prefilled friend mode from friend profiles, and empty-recipient mode from the postcard inbox header. Reuse the current preview and send pipeline after one friend is selected.

**Tech Stack:** SwiftUI, async/await, existing `PostcardComposerView`, `PostcardPreviewView`, `PostcardCenter`, XCTest.

---

### Task 1: Lock composer launch-state behavior with tests

**Files:**
- Create: `StreetStampsTests/PostcardComposerLaunchStateTests.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`

**Step 1: Write the failing test**

Add tests for:
- header-entry composer starts with no selected friend;
- friend-profile composer starts with the prefilled friend;
- preview remains disabled until one friend is selected.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardComposerLaunchStateTests`

Expected: FAIL because the composer currently requires `friendID` and `friendName`.

**Step 3: Write minimal implementation**

Refactor `PostcardComposerView` so it accepts an optional prefilled friend and exposes a lightweight launch-state helper that tests can assert.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/PostcardComposerLaunchStateTests.swift StreetStamps/PostcardComposerView.swift
git commit -m "test: cover postcard composer launch states"
```

### Task 2: Add recipient-picker UI to the existing composer

**Files:**
- Modify: `StreetStamps/PostcardComposerView.swift`
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/SocialGraphStore.swift`

**Step 1: Write the failing test**

Extend launch-state tests or add focused tests for:
- selecting one friend enables the flow;
- removing that friend disables preview again.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardComposerLaunchStateTests`

Expected: FAIL because no add-recipient UI exists.

**Step 3: Write minimal implementation**

Add a top recipient section that:
- shows the prefilled friend when present;
- shows an `添加收件人` action when empty;
- opens a simple friend picker from the existing friend list;
- allows clearing/changing the selected friend;
- passes the selected friend into `PostcardPreviewView`.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/PostcardComposerView.swift StreetStamps/PostcardPreviewView.swift StreetStamps/SocialGraphStore.swift StreetStampsTests/PostcardComposerLaunchStateTests.swift
git commit -m "feat: add postcard composer recipient picker"
```

### Task 3: Add the sent-box header envelope entry

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/MainTab.swift`

**Step 1: Write the failing test**

If a focused unit test is practical, add one for the new header action visibility. Otherwise keep this task implementation-first and verify through targeted build and manual behavior checks.

**Step 2: Write minimal implementation**

Add a top-right envelope button to the postcard inbox header that opens the composer in empty-recipient mode. Keep the existing friend-profile entry behavior unchanged.

**Step 3: Run targeted verification**

Run the composer launch-state tests and a simulator build command.

Expected: PASS.

**Step 4: Commit**

```bash
git add StreetStamps/PostcardInboxView.swift StreetStamps/FriendsHubView.swift StreetStamps/ProfileView.swift StreetStamps/MainTab.swift
git commit -m "feat: add postcard header compose entry"
```

### Task 4: Full verification

**Files:**
- Modify: any touched postcard files from earlier tasks

**Step 1: Run focused tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardComposerLaunchStateTests -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: PASS.

**Step 2: Run app build verification**

Run: `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: PASS.

**Step 3: Verify requirements checklist**

Verify:
- postcard sent-box header shows envelope button;
- header entry opens composer with no selected friend;
- selecting one friend enables preview/send flow;
- friend-profile entry still opens with a prefilled friend.

**Step 4: Commit**

```bash
git add StreetStamps StreetStampsTests docs/plans
git commit -m "feat: add postcard sent-box compose entry"
```
