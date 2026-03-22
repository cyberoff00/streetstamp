# Feed And Postcard Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `FriendsHubView` feed and `PostcardInboxView` use reminder-first refresh behavior instead of visible auto-refresh.

**Architecture:** Split refresh behavior into two paths: lightweight freshness checks that only raise prompt state, and full refresh actions that mutate rendered data only when the user explicitly refreshes or routing requires it. Reuse the current feed prompt pattern as the shared interaction model for feed and inbox.

**Tech Stack:** SwiftUI, async/await, existing `SocialGraphStore`, `PostcardCenter`, app scene phase handling

---

### Task 1: Add inbox refresh policy coverage

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Test: `StreetStampsTests/PostcardInboxRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Add tests for a small refresh-policy helper that covers:

- foreground return under 30 seconds does not trigger freshness check
- foreground return after 30 seconds triggers lightweight check
- prompt cooldown blocks repeated prompts inside 90 seconds
- lightweight check cooldown blocks repeated checks inside 5 minutes

**Step 2: Run test to verify it fails**

Run the smallest relevant test target and confirm the policy helper is missing.

**Step 3: Write minimal implementation**

Create the smallest helper needed to encode:

- `foregroundThreshold = 30`
- `lightweightCheckCooldown = 300`
- `promptCooldown = 90`

**Step 4: Run test to verify it passes**

Run the same test target and confirm it is green.

**Step 5: Commit**

Commit only the helper and its tests.

### Task 2: Remove postcard polling and add reminder-first inbox state

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Test: `StreetStampsTests/PostcardInboxRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Add tests for view-model-level logic or extracted helper methods that prove:

- automatic polling is gone
- lightweight check sets pending reminder state
- full refresh clears pending reminder state

**Step 2: Run test to verify it fails**

Run the targeted test and confirm current behavior still expects direct refresh.

**Step 3: Write minimal implementation**

Implement:

- remove the `.task` polling loop
- add pending inbox reminder state
- split lightweight check from full refresh
- keep first-load full refresh intact

**Step 4: Run test to verify it passes**

Run the targeted tests and confirm green.

**Step 5: Commit**

Commit the polling removal and reminder-first inbox logic.

### Task 3: Reuse feed-style prompt in postcard inbox

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Test: `StreetStampsTests/PostcardInboxRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Add tests for prompt visibility rules:

- prompt appears when pending inbox refresh is true
- prompt tap triggers full refresh
- prompt clears after successful refresh

**Step 2: Run test to verify it fails**

Run the targeted tests and confirm prompt behavior is missing.

**Step 3: Write minimal implementation**

Add the lightweight top prompt to the inbox screen, matching the feed interaction pattern as closely as current code structure allows.

**Step 4: Run test to verify it passes**

Run the targeted tests and confirm green.

**Step 5: Commit**

Commit the inbox prompt UI and interaction wiring.

### Task 4: Split feed freshness checks from feed application

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Test: `StreetStampsTests/FriendsFeedRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Add tests proving:

- lightweight feed checks only raise prompt state
- full refresh updates visible feed
- returning from background after threshold does not directly rewrite the list

**Step 2: Run test to verify it fails**

Run the targeted tests and confirm current feed refresh path is too direct.

**Step 3: Write minimal implementation**

Refactor feed refresh logic into:

- freshness check path
- user-applied refresh path
- targeted route refresh path

Preserve the existing prompt UI.

**Step 4: Run test to verify it passes**

Run the targeted tests and confirm green.

**Step 5: Commit**

Commit the feed refresh refactor.

### Task 5: Preserve deep-link and notification routing

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Test: `StreetStampsTests/PostcardInboxRefreshPolicyTests.swift`

**Step 1: Write the failing test**

Add tests proving deep-link / notification entry can still:

- fetch when needed
- open the correct inbox box
- focus the requested message without waiting for manual pull to refresh

**Step 2: Run test to verify it fails**

Run targeted tests and confirm route-specific refresh handling is incomplete.

**Step 3: Write minimal implementation**

Allow targeted full refresh for:

- postcard inbox deep links
- postcard notification entry
- feed routes that must display newly requested content immediately

**Step 4: Run test to verify it passes**

Run targeted tests and confirm green.

**Step 5: Commit**

Commit the routing-safe refresh handling.

### Task 6: Verify full behavior manually and with tests

**Files:**
- Modify: `docs/plans/2026-03-19-feed-and-postcard-refresh-implementation.md`

**Step 1: Run targeted tests**

Run all new refresh-policy tests.

**Step 2: Run broader project verification**

Run the smallest broader test suite or build command that covers the touched files.

**Step 3: Manual verification checklist**

Verify on device or simulator:

- feed initial load works
- feed pull to refresh works
- feed prompt appears instead of auto-reordering content
- inbox initial load works
- inbox no longer polls every 8 seconds
- inbox prompt appears for newly available content
- deep-link postcard focus still works

**Step 4: Record verification notes**

Add the exact commands and results to this plan or a follow-up validation note.

**Step 5: Commit**

Commit only if tests and manual checks both pass.
