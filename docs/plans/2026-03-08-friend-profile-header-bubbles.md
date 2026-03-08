# Friend Profile Header And Bubbles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the friend profile back/menu controls into a regular page header and restyle the welcome/postcard prompts as higher chat bubbles above the characters.

**Architecture:** Reuse the existing shared header pattern for the friend profile instead of keeping navigation controls inside the hero artwork. Keep the sofa scene component reusable, but extend its prompt bubble rendering so the friend page can show chat-style bubbles with a tail and tuned placement while preserving the existing seated-state logic.

**Tech Stack:** SwiftUI, XCTest, existing friend profile scene/state models

---

### Task 1: Lock the new scene copy in tests

**Files:**
- Modify: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`
- Modify: `StreetStamps/ProfileSceneInteractionState.swift`

**Step 1: Write the failing test**

Add assertions that seated friend profile state exposes `send a postcard?` and pre-seat state still exposes no postcard prompt.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests`

Expected: FAIL because the production copy still says `send a post card`.

**Step 3: Write minimal implementation**

Update the seated friend-profile prompt string in `ProfileSceneInteractionState`.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm `ProfileSceneInteractionStateTests` pass.

### Task 2: Move friend-profile controls into the regular header

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

No practical view test coverage exists for this SwiftUI header structure. Use the existing UI/state tests from Task 1 and keep this task intentionally minimal.

**Step 2: Write minimal implementation**

Replace the hero-embedded back/ellipsis controls with a `UnifiedTabPageHeader` above the scroll content. Keep the delete-friend menu logic unchanged.

**Step 3: Run verification**

Build the app target to confirm the view compiles.

### Task 3: Restyle the welcome/postcard prompts as chat bubbles above the avatars

**Files:**
- Modify: `StreetStamps/SofaProfileSceneView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

Rely on the prompt-copy/state test from Task 1 for the postcard appearance timing. Visual styling has no existing snapshot harness here.

**Step 2: Write minimal implementation**

Add a small chat-bubble variant with a tail in `SofaProfileSceneView`, move both prompts higher, and pass the friend page through the chat-bubble style. Keep postcard prompt rendering conditional on seated state only.

**Step 3: Run verification**

Build the app target and run the focused state tests.
