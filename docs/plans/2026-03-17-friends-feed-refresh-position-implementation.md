# Friends Feed Refresh And Position Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop the friends activity feed from auto-refreshing visible content, show a prompt when new feed items are detected, and return to the tapped feed card after leaving detail.

**Architecture:** Keep the rendered feed stable until the user explicitly refreshes it. Add a lightweight feed-update policy helper for diffing visible feed IDs, store the last opened feed event ID in view state, and restore scroll position through `ScrollViewReader` when navigation returns to the activity tab.

**Tech Stack:** SwiftUI, XCTest, existing `FriendsHubView` / `SocialGraphStore` feed pipeline.

---

### Task 1: Lock the feed-update policy with tests

**Files:**
- Create: `StreetStampsTests/FriendsFeedUpdatePromptPolicyTests.swift`
- Create: `StreetStamps/FriendsFeedUpdatePromptPolicy.swift`

**Step 1: Write the failing test**

Add tests for:
- returning `false` when the candidate feed has no unseen event IDs
- returning `true` when the candidate feed introduces a new event ID

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendsFeedUpdatePromptPolicyTests`

Expected: FAIL because `FriendsFeedUpdatePromptPolicy` does not exist yet.

**Step 3: Write minimal implementation**

Implement a small pure helper that compares currently displayed event IDs with a candidate list and reports whether there is unseen feed content.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new test target passes.

### Task 2: Lock the scroll-restoration state with tests

**Files:**
- Create: `StreetStamps/FriendsFeedScrollRestoreState.swift`
- Create: `StreetStampsTests/FriendsFeedScrollRestoreStateTests.swift`

**Step 1: Write the failing test**

Add tests for:
- remembering the last opened event ID
- producing a restore request when navigation returns
- clearing the pending restore request after it is consumed

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendsFeedScrollRestoreStateTests`

Expected: FAIL because the state helper is not implemented yet.

**Step 3: Write minimal implementation**

Implement a lightweight state container that tracks the last opened feed event and one-shot restore requests.

**Step 4: Run test to verify it passes**

Run the same command and confirm it passes.

### Task 3: Wire the friends feed UI to the new behavior

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/SocialGraphStore.swift`
- Test: `StreetStampsTests/FriendProfileSourceParityTests.swift`

**Step 1: Write the failing test**

Add source-parity assertions for:
- no 25-second auto-refresh loop in `FriendsHubView`
- new feed prompt copy and tap-to-refresh hook
- `ScrollViewReader` and last-opened feed event tracking

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendProfileSourceParityTests`

Expected: FAIL because the view does not yet contain the new flow.

**Step 3: Write minimal implementation**

Update the view to:
- remove the loop that directly refreshes visible feed content every 25 seconds
- use background polling only to detect unseen feed events and show a banner
- refresh the store only on initial load, user tap, pull-to-refresh, or explicit lifecycle transitions
- record the tapped event ID and scroll back to it when navigation returns

If needed, add a `SocialGraphStore` helper that fetches candidate friend snapshots without mutating the rendered state until the user accepts the refresh prompt.

**Step 4: Run test to verify it passes**

Run the same parity test command and confirm the assertions pass.

### Task 4: Run focused verification

**Files:**
- Test: `StreetStampsTests/FriendsFeedUpdatePromptPolicyTests.swift`
- Test: `StreetStampsTests/FriendsFeedScrollRestoreStateTests.swift`
- Test: `StreetStampsTests/FriendProfileSourceParityTests.swift`

**Step 1: Run focused tests**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendsFeedUpdatePromptPolicyTests -only-testing:StreetStampsTests/FriendsFeedScrollRestoreStateTests -only-testing:StreetStampsTests/FriendProfileSourceParityTests
```

Expected: PASS for all targeted tests.

**Step 2: Summarize residual risk**

Call out that the visual scroll jump behavior still benefits from manual simulator verification because `ScrollViewReader` timing is hard to fully prove in source-level tests alone.
