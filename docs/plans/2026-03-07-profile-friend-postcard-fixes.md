# Profile Friend Postcard Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix account-mode avatar persistence on Profile, enlarge the avatar scene on Profile and friend pages, and move the friend postcard entry into the seated scene bubble.

**Architecture:** Keep avatar persistence aligned with the existing user-scoped profile state system instead of relying on raw global `UserDefaults` access from views. Keep the friend postcard UX state-driven by extending `ProfileSceneInteractionState` so the bubble only appears after the visitor sits, then wire the bubble tap to the existing postcard composer route. Apply the avatar size change centrally in `SofaProfileSceneView` so both screens stay visually consistent.

**Tech Stack:** SwiftUI, XCTest, app-scoped `UserDefaults`, existing `ProfileSceneInteractionState` and `RobotLoadout` models.

---

### Task 1: Cover the broken persistence and seated CTA behavior with tests

**Files:**
- Modify: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`
- Modify: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Write the failing test**

Add a test proving that saving a loadout for the active account updates both the global key and the scoped account key. Add a second test proving the friend-profile state exposes a postcard prompt only after the visitor is seated.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests`

Expected: the new assertions fail because no helper syncs avatar saves into the user-scoped store and the interaction state has no postcard prompt signal.

**Step 3: Write minimal implementation**

Add the smallest API needed in the production code to satisfy the tests.

**Step 4: Run test to verify it passes**

Re-run the same focused test command and confirm both suites pass.

**Step 5: Commit**

Commit message: `fix: preserve scoped avatars and seat-gated postcard CTA`

### Task 2: Route profile avatar saves through the scoped store

**Files:**
- Modify: `StreetStamps/UserScopedProfileStateStore.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/EquipmentView.swift`

**Step 1: Write the failing test**

Use the Task 1 persistence test as the red case for this implementation.

**Step 2: Run test to verify it fails**

Run the focused persistence suite and confirm the new save-path assertion fails.

**Step 3: Write minimal implementation**

Add a `saveCurrentLoadout(_:for:defaults:)` helper to `UserScopedProfileStateStore`. In `ProfileView`, initialize and persist the avatar using the current active user identity from `sessionStore` instead of raw `AvatarLoadoutStore.save`. Remove duplicate persistence from `EquipmentView` so the bound parent owns saving.

**Step 4: Run test to verify it passes**

Run the persistence suite again.

**Step 5: Commit**

Commit message: `fix: scope profile avatar saves by user`

### Task 3: Move the friend postcard entry into the seated scene bubble and enlarge the characters

**Files:**
- Modify: `StreetStamps/ProfileSceneInteractionState.swift`
- Modify: `StreetStamps/SofaProfileSceneView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

Use the Task 1 scene-state test as the red case for the seated postcard prompt.

**Step 2: Run test to verify it fails**

Run the focused scene-state suite and confirm the postcard prompt expectation fails.

**Step 3: Write minimal implementation**

Extend `ProfileSceneInteractionState` with a derived prompt string or boolean. In `FriendsHubView`, remove the standalone `SEND POSTCARD` card and overlay a tappable bubble in the hero scene only when the user has already sat down. Reuse the existing `PostcardComposerView`. Increase the shared avatar scale in `SofaProfileSceneView`, then rebalance the offsets/frame usage in Profile and friend hero sections so both views render larger characters without clipping.

**Step 4: Run test to verify it passes**

Run the focused scene-state suite and then a targeted build/test pass for the touched UI container tests if needed.

**Step 5: Commit**

Commit message: `feat: move postcard entry into seated profile scene`
