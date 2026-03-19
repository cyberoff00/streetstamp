# Friends Feed Social Dynamic Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rework the friends feed so it feels like a lightweight Instagram-style social dynamic stream without adding image previews or changing feed data sources.

**Architecture:** Keep the existing feed event pipeline and navigation/refresh behavior, but introduce a dedicated presentation helper for social sentence composition and rebuild the card layout around actor, action, secondary context, and engagement. Preserve the current feed ordering, like policy, refresh prompt, and scroll restoration.

**Tech Stack:** SwiftUI, XCTest, existing `FriendsHubView` feed event pipeline, localization via `L10n`

---

### Task 1: Lock social sentence presentation with tests

**Files:**
- Create: `StreetStamps/FriendsFeedSocialPresentation.swift`
- Create: `StreetStampsTests/FriendsFeedSocialPresentationTests.swift`

**Step 1: Write the failing test**

Add tests for:
- generating a journey-style social sentence
- generating a memory-style social sentence that includes count context when appropriate
- generating a city-unlock social sentence with stronger milestone wording
- returning secondary location/context strings without reusing the primary sentence shape

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendsFeedSocialPresentationTests`

Expected: FAIL because `FriendsFeedSocialPresentation` does not exist yet.

**Step 3: Write minimal implementation**

Implement a pure presentation helper that:
- maps `FriendFeedKind` to a primary social sentence
- provides a secondary support line for city/location or event-specific context
- centralizes decisions about whether badge text is still needed

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new tests pass.

### Task 2: Rebuild feed event presentation fields

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Test: `StreetStampsTests/FriendProfileSourceParityTests.swift`

**Step 1: Write the failing test**

Add/update parity assertions for:
- presence of `FriendsFeedSocialPresentation`
- feed card using a primary social sentence and secondary context
- engagement row staying present

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendProfileSourceParityTests`

Expected: FAIL because the view still uses the old card presentation.

**Step 3: Write minimal implementation**

Update `FriendsHubView.swift` to:
- extend `FriendFeedEvent` with the fields required by the new social card
- compute primary and secondary presentation values through `FriendsFeedSocialPresentation`
- preserve current feed ordering and refresh detection behavior

**Step 4: Run test to verify it passes**

Run the same parity test command and confirm the assertions pass.

### Task 3: Convert `FriendActivityCard` into a social dynamic card

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

If needed, expand the existing parity test to assert:
- header-first structure with display name and recency
- social sentence body replacing the old title/location emphasis
- footer row containing engagement and metadata support text

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendProfileSourceParityTests`

Expected: FAIL because the card layout is still the old structure.

**Step 3: Write minimal implementation**

Refactor the card so that it:
- uses a stronger social header/body hierarchy
- visually differentiates `city`, `memory`, and `journey` cards without introducing images
- demotes or removes redundant badge presentation
- makes the like affordance feel like a social response row

**Step 4: Run test to verify it passes**

Run the same parity test command and confirm the assertions pass.

### Task 4: Focused verification

**Files:**
- Test: `StreetStampsTests/FriendsFeedSocialPresentationTests.swift`
- Test: `StreetStampsTests/FriendsFeedLikePresentationTests.swift`
- Test: `StreetStampsTests/FriendsFeedUpdatePromptPolicyTests.swift`
- Test: `StreetStampsTests/FriendsFeedScrollRestoreStateTests.swift`
- Test: `StreetStampsTests/FriendProfileSourceParityTests.swift`

**Step 1: Run focused tests**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendsFeedSocialPresentationTests -only-testing:StreetStampsTests/FriendsFeedLikePresentationTests -only-testing:StreetStampsTests/FriendsFeedUpdatePromptPolicyTests -only-testing:StreetStampsTests/FriendsFeedScrollRestoreStateTests -only-testing:StreetStampsTests/FriendProfileSourceParityTests
```

Expected: PASS for all targeted tests.

**Step 2: Manual verification**

Check in simulator:
- feed cards feel socially scannable
- self-post navigation and friend-post navigation still open the right destinations
- scroll restoration still returns near the tapped card
- refresh prompt still appears without jarring visible-feed replacement

**Step 3: Commit**

```bash
git add StreetStamps/FriendsFeedSocialPresentation.swift StreetStamps/FriendsHubView.swift StreetStampsTests/FriendsFeedSocialPresentationTests.swift StreetStampsTests/FriendProfileSourceParityTests.swift docs/plans/2026-03-18-friends-feed-social-dynamic-design.md docs/plans/2026-03-18-friends-feed-social-dynamic-implementation.md
git commit -m "feat: redesign friends feed as social dynamic stream"
```
