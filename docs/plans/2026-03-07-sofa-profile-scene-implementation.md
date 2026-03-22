# Sofa Profile Scene Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a reusable sofa-scene header for my profile and friend profiles, and change the friend-page interaction from "踩一踩主页" to a local immediate "坐一坐" experience.

**Architecture:** Introduce one shared SwiftUI scene component plus a small pure helper for display/interaction state so the behavior can be tested without UI harnesses. Reuse `RobotRendererView`, keep the existing `stompProfile` backend call, and wire local seated-state only inside `FriendProfileScreen`.

**Tech Stack:** Swift, SwiftUI, XCTest, xcodebuild

---

### Task 1: Add failing tests for scene-state rules

**Files:**
- Create: `StreetStamps/ProfileSceneInteractionState.swift`
- Create: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Write the failing test**

- Add pure XCTest coverage for:
  - my profile renders one centered avatar and no welcome bubble
  - friend profile before action renders host-left, visitor-hidden, welcome bubble visible, CTA enabled
  - friend profile after success renders host-left, visitor-right, welcome bubble visible, CTA disabled
  - self-viewed friend page suppresses CTA

**Step 2: Run test to verify it fails**

- Run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests
```
- Expected: fail because the helper type and rules do not exist yet.

**Step 3: Write minimal implementation**

- Add a pure helper that resolves:
  - host seat position
  - optional visitor seat position
  - welcome bubble visibility
  - CTA visibility / enabled state
  - CTA copy for idle, loading, and seated states

**Step 4: Run test to verify it passes**

- Re-run the focused `xcodebuild test` command above.

**Step 5: Commit**

```bash
git add StreetStamps/ProfileSceneInteractionState.swift StreetStampsTests/ProfileSceneInteractionStateTests.swift
git commit -m "test: add profile scene interaction rules"
```

### Task 2: Build the reusable sofa-scene component

**Files:**
- Create: `StreetStamps/SofaProfileSceneView.swift`
- Modify: `StreetStamps/ProfileSceneInteractionState.swift`
- Modify: `StreetStamps.xcodeproj/project.pbxproj`
- Test: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Write the failing test**

- Extend helper tests only if needed to cover any extra scene-state branch required by the component API.

**Step 2: Implement the shared scene**

- Build a reusable SwiftUI view that renders:
  - soft teal rounded room card
  - couch silhouette
  - right-side floor lamp
  - optional host `Welcome!` bubble
  - one or two `RobotRendererView` avatars positioned per helper state
- Keep all geometry and colors local to the component so `ProfileView` and `FriendProfileScreen` do not duplicate layout math.

**Step 3: Run the focused tests**

- Re-run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests
```

**Step 4: Run a build to verify the new file is wired into the target**

- Run:
```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

**Step 5: Commit**

```bash
git add StreetStamps/SofaProfileSceneView.swift StreetStamps/ProfileSceneInteractionState.swift StreetStamps.xcodeproj/project.pbxproj
git commit -m "feat: add reusable sofa profile scene"
```

### Task 3: Integrate the scene into my profile

**Files:**
- Modify: `StreetStamps/ProfileView.swift`
- Test: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Replace the existing avatar hero area**

- Swap the current glowing avatar block inside `avatarHeaderCard` for `SofaProfileSceneView`.
- Render the current user in the centered-seat mode.
- Preserve name editing, level progress, stats, and existing lower cards.

**Step 2: Keep current affordances aligned**

- Reposition or overlay the equipment entry only if needed so it remains reachable without visually fighting the Figma scene.

**Step 3: Run build verification**

- Run:
```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

**Step 4: Commit**

```bash
git add StreetStamps/ProfileView.swift
git commit -m "feat: use sofa scene on my profile"
```

### Task 4: Integrate the scene and local sit-together state into friend profiles

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/BackendAPIClient.swift` (only if copy helpers or response wording normalization becomes necessary)
- Test: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`

**Step 1: Replace the friend avatar hero area**

- Swap the current friend avatar block inside `FriendProfileScreen` for `SofaProfileSceneView`.
- Render host-left with the fixed `Welcome!` bubble.

**Step 2: Add local seated-state flow**

- Add local `@State` for visitor seating.
- Start unseated.
- On successful `stompProfile`, set seated state to `true`.
- Do not optimistically seat before success.

**Step 3: Replace old stomp copy with sitting copy**

- Change:
  - CTA label from `踩一踩主页` to `坐一坐`
  - loading text to `坐下中...` or equivalent
  - success toast to sitting language
  - failure toast prefix to `坐一坐失败`
- Suppress the CTA when viewing self.

**Step 4: Run focused tests and build**

- Run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSceneInteractionStateTests
```

- Then run:
```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift StreetStamps/BackendAPIClient.swift
git commit -m "feat: add sit together friend profile scene"
```

### Task 5: Final verification and implementation notes

**Files:**
- Modify: `docs/plans/2026-03-07-sofa-profile-scene-implementation.md`

**Step 1: Run final manual QA**

- Verify:
  - my profile centers my avatar on the sofa
  - friend profiles show host-left plus fixed `Welcome!`
  - tapping `坐一坐` only seats the visitor after success
  - failed requests leave the visitor seat empty
  - city library, journey memory, send postcard, and delete-friend flows still work

**Step 2: Record any deviations**

- Update this plan with concise notes if:
  - exact Figma proportions required spacing compromise
  - the equipment button needed repositioning
  - copy had to be normalized because of backend-returned messages

**Step 3: Commit**

```bash
git add docs/plans/2026-03-07-sofa-profile-scene-implementation.md
git commit -m "docs: update sofa profile implementation notes"
```

---

## Execution Notes

- 2026-03-07: `StreetStamps.xcscheme` has an empty `TestAction` and the project file does not currently define a `StreetStampsTests` target, so `StreetStampsTests/ProfileSceneInteractionStateTests.swift` was added as coverage for the scene-state rules but could not be executed in this repository state.
- 2026-03-07: Build verification succeeded with:

```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedDataSofa -clonedSourcePackagesDirPath build/SourcePackages
```
