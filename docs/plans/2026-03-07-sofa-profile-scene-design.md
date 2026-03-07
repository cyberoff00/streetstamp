# Sofa Profile Scene Design

Date: 2026-03-07
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps` currently renders profile pages as avatar-centric cards:

- [`StreetStamps/ProfileView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ProfileView.swift) shows the current user's profile card
- [`StreetStamps/FriendsHubView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FriendsHubView.swift) contains `FriendProfileScreen` for friend profiles

The current friend profile interaction is a backend-backed `stompProfile` action presented as "踩一踩主页". The approved product direction is to replace that visual metaphor with a shared "sofa scene" inspired by Figma node `172:6` in file `wy0b6jKyQt6om7mtEazlmM`.

The user-approved behavior is:

- my own profile shows only me sitting in the center of a two-seat sofa
- friend profiles show the friend seated on the left
- the friend profile always shows a fixed `welcome` speech bubble above the host
- tapping `坐一坐` should place my avatar beside the friend on the right
- this first iteration is local immediate UI state only, not cross-device synced state

## Goal

Build a reusable SwiftUI sofa-scene header shared by my profile and friend profile pages, with Figma-aligned room styling and a local "sit together" interaction layered on top of the existing backend stomp endpoint.

## Non-Goals

- no backend schema or API contract changes
- no real-time or persistent cross-user seating state
- no redesign of lower profile sections such as stats, cities, memories, or postcard entry points
- no replacement of the existing avatar renderer system

## Figma Reference

Primary reference:

- file key: `wy0b6jKyQt6om7mtEazlmM`
- node id: `172:6`
- node name: `Combined Avatar Section (Friend + Me Visiting)`

Important visual traits from the Figma payload:

- soft teal room card with rounded corners
- couch silhouette near the lower half of the scene
- small floor lamp on the upper-right side
- host avatar positioned on the left
- fixed `Welcome!` speech bubble above the host
- CTA button labeled `坐一坐`
- the second seat is intentionally empty before the visitor sits down

## Existing Constraints

### 1. Profile Layouts Already Depend on Existing Card Structure

Both profile pages already use vertically stacked cards and Figma-themed styling. The sofa scene should replace only the top avatar presentation area and should not force a layout rewrite of surrounding sections.

### 2. Friend Interaction Already Depends on `stompProfile`

The app already exposes a profile interaction through:

- [`StreetStamps/BackendAPIClient.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/BackendAPIClient.swift) `stompProfile(token:targetUserID:)`
- [`StreetStamps/FriendsHubView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FriendsHubView.swift) `sendProfileStomp(to:)`

For this iteration, the safest path is to keep that endpoint and change the front-end semantics from "踩一踩" to "坐一坐".

### 3. Avatars Are Already Rendered Through `RobotRendererView`

The scene should reuse `RobotRendererView` and current loadout data rather than introduce another avatar implementation path. This keeps visual identity consistent across the app and avoids touching avatar asset pipelines.

## Proposed Architecture

### 1. Add a Shared Sofa Scene View

Create a dedicated SwiftUI component, tentatively `SofaProfileSceneView`, under [`StreetStamps`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps).

The shared component should own only the scene rendering concerns:

- room background card
- couch silhouette
- lamp/decor shape
- grounding shadow/floor accent
- avatar seat positions
- optional host speech bubble
- optional visitor avatar seat occupancy

The component should not own page navigation, data loading, or backend calls.

### 2. Drive the Scene with Explicit Display Modes

The scene should support two approved display modes:

- `myProfile`
- `friendProfile`

Recommended inputs:

- `mode`
- `hostLoadout`
- `visitorLoadout` if needed
- `showsWelcomeBubble`
- `isVisitorSeated`

Expected rendering:

- `myProfile`: render only the current user centered on the sofa
- `friendProfile` before interaction: render the friend on the left and keep the right seat empty
- `friendProfile` after interaction: render the friend on the left and the current user on the right

### 3. Keep Seating State Local to `FriendProfileScreen`

The approved first version is not synced state. Therefore:

- `FriendProfileScreen` should own a local `@State` such as `isVisitorSeated`
- initial value should be `false`
- successful completion of the existing interaction request flips the state to `true`
- leaving and reopening the screen does not need guaranteed persistence

This keeps the implementation honest about what is and is not shared with other users.

### 4. Preserve Backend Behavior but Reframe the UI Copy

The current action still uses `stompProfile`, but the interface should present it as sitting together.

Approved copy direction:

- button: `坐一坐`
- loading: `发送中...` can be updated to `坐下中...`
- success toast: use sitting language such as `你坐到了 XXX 身边`
- failure toast: `坐一坐失败：...`

This preserves the notification/backend chain while aligning the surface language with the new design metaphor.

## UI Behavior

### My Profile

In [`StreetStamps/ProfileView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ProfileView.swift):

- replace the current glowing avatar hero area with the new sofa scene
- render the current user seated in the center of the sofa
- do not show the `welcome` speech bubble
- keep the display name, level, progress, and stats below the scene
- keep existing edit/equipment affordances unless layout constraints require a small reposition

### Friend Profile

In [`StreetStamps/FriendsHubView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FriendsHubView.swift):

- replace the current avatar hero area with the new sofa scene
- render the friend on the left by default
- render a fixed `welcome` bubble above the friend at all times
- keep the right seat empty until the user taps `坐一坐`
- after success, show the current user's avatar on the right
- disable or visually settle the button after seating succeeds to avoid repeated submissions

### CTA Behavior

For friend profiles only:

- if the page belongs to another user, show the CTA
- if the current account user is the same as `friendID`, do not show the CTA
- only show the visitor avatar once the backend action succeeds
- do not optimistically seat the visitor before request success

## Data Flow

### Friend Profile Request Path

1. User opens a friend profile
2. `FriendProfileScreen` loads the friend snapshot as it does today
3. Scene renders friend-left, empty-right, and fixed `welcome` bubble
4. User taps `坐一坐`
5. Existing `BackendAPIClient.shared.stompProfile(...)` request is sent
6. On success:
   - toast text uses sitting language
   - local `isVisitorSeated` becomes `true`
7. On failure:
   - toast shows failure
   - `isVisitorSeated` remains `false`

### My Profile Data Path

My profile continues to use the local current-user loadout already managed by `ProfileView`. Only the presentation changes.

## Edge Cases

- if the user is not logged in, reuse the existing auth guard behavior and do not enter seated state
- if the request fails, do not render the visitor avatar
- if the friend snapshot is temporarily unavailable, the fallback friend still renders with the same left-seat layout
- if the viewer is effectively viewing self content, suppress the `坐一坐` CTA
- the `welcome` bubble is display-only and should not depend on `bio`, notifications, or backend fields

## Testing Strategy

### Manual Verification

1. Open my profile and verify the sofa scene shows only my avatar centered
2. Open a friend profile and verify the friend appears on the left with a fixed `welcome` bubble
3. Verify the right seat is empty before interaction
4. Tap `坐一坐` and verify my avatar appears on the right only after success
5. Force a failed request and verify no visitor avatar appears
6. Verify existing entries below the scene still work:
   - city library
   - journey memory
   - send postcard
   - delete friend

### Regression Focus

- profile stats layout
- friend profile navigation destinations
- toast presentation
- current avatar loadout rendering
- self-versus-friend CTA visibility

## Implementation Notes

- prefer shape-based SwiftUI drawing for the sofa/lamp/background instead of introducing new asset files unless visual fidelity clearly requires them
- keep the scene reusable and avoid duplicating geometry in `ProfileView` and `FriendProfileScreen`
- if exact Figma proportions conflict with current page spacing, preserve the scene composition first and minimally adjust surrounding vertical spacing

## Acceptance Criteria

1. My profile shows a sofa background scene with my avatar seated in the middle
2. Friend profiles show the host seated on the left with a fixed `welcome` bubble
3. Friend profiles expose a `坐一坐` CTA instead of `踩一踩主页`
4. Tapping `坐一坐` uses the existing backend action and only seats the visitor after success
5. Failure leaves the visitor seat empty and shows sitting-themed error copy
6. Lower friend-profile features remain unchanged and functional
