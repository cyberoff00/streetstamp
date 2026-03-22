# Profile Notification And Level Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the profile hero by moving level UI into the progress row, showing social notifications only as a conditional cloud affordance on the hero, and reducing the invite entry to a single line.

**Architecture:** Keep the existing `ProfileView` structure, but extract the notification/level presentation rules into a small helper that can be unit-tested. Reuse the current notification sheet and friend-notification visual pattern instead of creating new navigation or state containers.

**Tech Stack:** SwiftUI, XCTest, existing StreetStamps profile and friends UI components

---

### Task 1: Add regression coverage for profile header presentation

**Files:**
- Create: `StreetStampsTests/ProfileHeaderPresentationTests.swift`
- Create: `StreetStamps/ProfileHeaderPresentation.swift`

**Step 1: Write the failing test**

```swift
func test_cloud_is_hidden_without_notifications()
func test_cloud_is_visible_with_notifications()
func test_level_help_message_uses_remaining_journeys()
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileHeaderPresentationTests`
Expected: FAIL because `ProfileHeaderPresentation` does not exist yet.

**Step 3: Write minimal implementation**

Add a small helper with:
- `showsNotificationCloud(notificationCount:)`
- `levelHelpText(remainingJourneys:)`

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS for the new test class.

### Task 2: Update profile hero layout and actions

**Files:**
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/ProfileHeroComponents.swift`
- Modify: `StreetStamps/SofaProfileSceneView.swift`

**Step 1: Wire hero controls**

- Remove the level pill from the nickname row.
- Replace the old progress button/alert flow with a narrow centered progress bar row.
- Add the level pill on the left and a help button on the right.
- Show a lightweight bubble with `还差 X 段旅程升级`.

**Step 2: Move notification entry**

- Remove the standalone social notification tile from the action list.
- Add an optional cloud button to the hero's top-left overlay.
- Only render it when helper logic says notifications exist.
- Preserve unread badge behavior and open the existing notification sheet.

**Step 3: Simplify invite entry**

- Keep only the single-line `邀请好友` title in the invite tile.

**Step 4: Verify manually in code**

- Confirm the profile still loads notifications on task/on-change hooks.
- Confirm postcard entry remains unchanged.

### Task 3: Verify the change

**Files:**
- No code changes expected

**Step 1: Run focused tests**

Run the targeted `xcodebuild test` command for `ProfileHeaderPresentationTests`.

**Step 2: Run a focused build**

Run: `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -derivedDataPath build/DerivedDataProfileHero`

**Step 3: Inspect diff**

Run: `git diff -- StreetStamps/ProfileView.swift StreetStamps/ProfileHeroComponents.swift StreetStamps/SofaProfileSceneView.swift StreetStamps/ProfileHeaderPresentation.swift StreetStampsTests/ProfileHeaderPresentationTests.swift`

**Step 4: Commit**

```bash
git add StreetStamps/ProfileView.swift StreetStamps/ProfileHeroComponents.swift StreetStamps/SofaProfileSceneView.swift StreetStamps/ProfileHeaderPresentation.swift StreetStampsTests/ProfileHeaderPresentationTests.swift docs/plans/2026-03-07-profile-notification-level-design.md docs/plans/2026-03-07-profile-notification-level-implementation.md
git commit -m "feat: refine profile notification and level layout"
```
