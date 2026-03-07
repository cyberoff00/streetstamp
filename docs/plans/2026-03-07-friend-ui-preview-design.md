# Friend UI Preview Design

**Date:** 2026-03-07

**Goal:** Add a local-only debug page reachable from Settings so the user can inspect the friend profile UI, including the "坐一坐" seated state, without requiring backend data or a real friend relationship.

## Context

The existing friend profile experience lives inside [`FriendsHubView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FriendsHubView.swift) and depends on `SocialGraphStore` snapshots plus backend-driven actions. During testing, the account may not have any friends, which blocks visual verification of the profile scene and seated interaction.

## Approach

Create a standalone SwiftUI debug screen under Settings' existing `DEBUG TOOLS` area. The screen will:

- Use hardcoded local mock friend data
- Reuse the existing `SofaProfileSceneView`
- Drive "坐一坐" entirely from local `@State`
- Show the same high-level layout shape as the real friend profile page
- Avoid any backend requests, friend store mutations, or navigation into real friend data flows

## Scope

In scope:

- Add a `FRIEND UI PREVIEW` row under Settings debug tools
- Build a standalone preview page with mock profile header, stats, and action tiles
- Support toggling between unseated and seated scene states locally
- Add unit coverage for the preview data factory / local interaction state

Out of scope:

- Real friend loading
- Backend calls
- Reusing `FriendProfileScreen` directly
- Making the mock cards functional beyond visual preview

## Data Model

Add a tiny local preview model/factory that returns:

- A `FriendProfileSnapshot` mock
- A local `ProfileSceneInteractionState`
- A visitor loadout based on the current local avatar

This keeps the preview page deterministic and testable without coupling to `SocialGraphStore`.

## Validation

- Unit test the preview factory so the mock snapshot is non-empty and seated state resolves correctly
- Run the targeted profile scene tests plus the new preview test
- Run a targeted app build check to catch SwiftUI compile issues
