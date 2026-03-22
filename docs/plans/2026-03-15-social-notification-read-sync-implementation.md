# Social Notification Read Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the profile notification entry and friends activity notification entry visually synchronized when notifications are marked read in either place.

**Architecture:** Introduce a tiny `NotificationCenter`-backed sync helper that broadcasts successful read mutations across the app. Both `ProfileView` and `FriendsHubView` will keep their existing local arrays, but they will observe the shared event and apply the same read-state mutation locally.

**Tech Stack:** Swift, SwiftUI, XCTest, NotificationCenter

---

### Task 1: Add the failing sync helper tests

**Files:**
- Create: `StreetStampsTests/SocialNotificationReadSyncTests.swift`

**Step 1: Write the failing test**

```swift
func test_applyMarksSpecifiedNotificationsRead() {
    let updated = SocialNotificationReadSync.applying(
        .init(ids: ["n2"], markAll: false),
        to: sampleItems()
    )

    XCTAssertTrue(updated[1].read)
    XCTAssertFalse(updated[0].read)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/SocialNotificationReadSyncTests`
Expected: FAIL because `SocialNotificationReadSync` does not exist yet.

**Step 3: Write minimal implementation**

```swift
enum SocialNotificationReadSync {
    struct Payload {
        let ids: Set<String>
        let markAll: Bool
    }

    static func applying(_ payload: Payload, to items: [BackendNotificationItem]) -> [BackendNotificationItem] {
        ...
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/SocialNotificationReadSyncTests`
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStampsTests/SocialNotificationReadSyncTests.swift StreetStamps/SocialNotificationReadSync.swift
git commit -m "test: cover social notification read sync"
```

### Task 2: Broadcast read-sync events from both entry points

**Files:**
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing integration-shaped assertion mentally against current behavior**

```swift
// After mark-read succeeds in one surface, the peer surface still shows the item unread.
```

**Step 2: Add the shared sync observer and helper usage**

```swift
.onReceive(NotificationCenter.default.publisher(for: .socialNotificationsDidMarkRead)) { notification in
    applySocialNotificationReadSync(notification)
}
```

**Step 3: Broadcast successful changes after backend success**

```swift
SocialNotificationReadSync.post(ids: targetIDs, markAll: false)
```

and

```swift
SocialNotificationReadSync.post(ids: unreadIDs, markAll: true)
```

**Step 4: Verify local behavior**

Run: same focused test target plus the app test suite subset if needed.
Expected: tests stay green and both screens share the same visual read state immediately.

**Step 5: Commit**

```bash
git add StreetStamps/ProfileView.swift StreetStamps/FriendsHubView.swift StreetStamps/SocialNotificationReadSync.swift
git commit -m "fix: sync social notification read state across entry points"
```

### Task 3: Verify the focused test suite

**Files:**
- Test: `StreetStampsTests/SocialNotificationReadSyncTests.swift`

**Step 1: Run focused verification**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/SocialNotificationReadSyncTests`
Expected: PASS

**Step 2: Run a second lightweight regression test if needed**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileHeaderPresentationTests`
Expected: PASS

**Step 3: Commit**

```bash
git add docs/plans/2026-03-15-social-notification-read-sync-design.md docs/plans/2026-03-15-social-notification-read-sync-implementation.md
git commit -m "docs: add social notification read sync plan"
```
