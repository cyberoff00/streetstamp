# Figma Profile Hero Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply the new Figma-style hero to the friend profile and align my profile card’s sofa backdrop to the same mint scene language.

**Architecture:** Refactor the sofa scene into reusable artwork and introduce a small shared set of hero chrome components for mint background, level badge, and stat summary. Compose the friend hero as a full-bleed section and the self hero as an embedded card section on top of the existing profile layout.

**Tech Stack:** SwiftUI, existing profile/friend views, existing robot renderer

---

### Task 1: Lock Shared Hero State Inputs

**Files:**
- Modify: `StreetStampsTests/ProfileSceneInteractionStateTests.swift`
- Test: `StreetStampsTests/DebugFriendProfilePreviewTests.swift`

**Step 1: Write the failing test**

Add/keep focused assertions around friend seated state and my-profile center-seat state so the shared scene refactor does not change interaction mapping.

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command if the scheme supports it.

Expected: In this repository state the shared scheme still does not expose a runnable XCTest target, so test execution remains blocked even though the source coverage is present.

**Step 3: Write minimal implementation**

Do not change interaction state rules while restyling the hero.

**Step 4: Run test to verify it passes**

Re-run if scheme support exists; otherwise document the limitation and proceed with build validation.

### Task 2: Refactor Shared Sofa Scene Chrome

**Files:**
- Modify: `StreetStamps/SofaProfileSceneView.swift`
- Create: `StreetStamps/ProfileHeroComponents.swift`

**Step 1: Write the failing test**

Reuse the state coverage from Task 1 as the guardrail.

**Step 2: Run test to verify it fails**

Blocked by the current shared scheme’s missing test target.

**Step 3: Write minimal implementation**

- Make `SofaProfileSceneView` render the sofa artwork layer rather than a fully boxed card
- Add shared mint backdrop, level pill, stat card, and glass button helpers

**Step 4: Run test to verify it passes**

Validate by app build.

### Task 3: Apply Friend And Self Hero Layouts

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/DebugFriendProfilePreviewView.swift`

**Step 1: Write the failing test**

Use the already-added preview/state coverage as the contract.

**Step 2: Run test to verify it fails**

Blocked by current scheme configuration.

**Step 3: Write minimal implementation**

- Friend profile: full-bleed mint hero matching the Figma composition
- My profile: same sofa backdrop language inside the existing rounded card
- Debug preview: align with the updated friend hero so the local preview remains representative

**Step 4: Run test to verify it passes**

Run:

- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: `BUILD SUCCEEDED`
