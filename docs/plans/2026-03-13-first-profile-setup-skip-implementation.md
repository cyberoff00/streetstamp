# First Profile Setup Skip Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to skip the first profile setup screen from the top-right action while still requiring a non-empty nickname and marking setup as completed so it does not reappear.

**Architecture:** Keep the existing `/v1/profile/setup` completion path as the single source of truth. Add a skip affordance in the SwiftUI screen that reuses the same submission flow, validates nickname presence before either action succeeds, and clears the local pending state through the existing session store callback.

**Tech Stack:** SwiftUI, existing iOS session state management, existing backend profile setup endpoint

---

### Task 1: Cover the new screen behavior

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FirstProfileSetupView.swift`
- Test: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStampsTests/FirstProfileSetupViewTests.swift`

**Step 1: Write the failing test**

Add a focused view-level/unit-level test that proves the skip action is exposed and that the shared submission path rejects an empty nickname before completion.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FirstProfileSetupViewTests`

Expected: FAIL because skip behavior is not implemented yet.

**Step 3: Write minimal implementation**

Add a skip button in the navigation chrome, route both confirm and skip through one async submission helper, and keep nickname validation shared.

**Step 4: Run test to verify it passes**

Run the same targeted `xcodebuild test` command and confirm PASS.

### Task 2: Verify setup completion still clears the pending state

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FirstProfileSetupView.swift`
- Verify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/Usersessionstore.swift`

**Step 1: Reuse the existing backend completion path**

Ensure skip and confirm both call the same completion request, then preserve the current `markProfileSetupCompleted()` flow.

**Step 2: Verify no repeated setup**

Run a targeted build or test that exercises the screen and confirm the view still clears the local pending flag after success.

### Task 3: Validate and deploy

**Files:**
- Verify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FirstProfileSetupView.swift`

**Step 1: Run verification**

Run the targeted UI-related test/build command and capture the result.

**Step 2: Deploy**

If only client code changed, note that a new app build is required rather than a backend deployment. If any backend change is discovered during implementation, deploy it and confirm health.
