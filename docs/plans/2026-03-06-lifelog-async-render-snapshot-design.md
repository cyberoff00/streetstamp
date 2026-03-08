# Lifelog Async Render Snapshot Design

Date: 2026-03-06
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps/LifelogView.swift` still computes multiple render fallbacks synchronously during view evaluation. Even after moving unified render event preparation off the main actor, `LifelogView` still has several paths that synchronously call `UnifiedLifelogRenderProvider.segments(...)`, rebuild route runs, and derive center coordinates on demand.

This keeps `Lifelog` vulnerable to visible stalls when:

- entering the page with a large history
- switching selected day
- changing viewport / zoom enough to invalidate the visible region
- reading source-backed fallback data while derived tiles are missing or stale

## Goal

Keep `Lifelog` responsive by changing it from render-time computation to state-driven asynchronous render snapshots, while preserving:

- the robot marker and current-location display
- near-mode footprint rendering
- far-mode route segment rendering
- selected-day recentering behavior
- existing route semantics and fallback order

## Non-Goals

- no redesign of `Lifelog` UI
- no changes to globe rendering in this task
- no persistent cache format changes
- no speculative refactor of unrelated `LifelogView` state

## Root Cause

The remaining lag is caused less by a single API call and more by the fact that `LifelogView` still does heavy derived work inside synchronous render helpers:

- path coordinate fallback resolution
- far-route run building
- footprint run building
- selected-day center fallback lookup
- multiple synchronous refresh triggers

Even if each individual helper becomes `async`, the page will still be fragile unless the entire derived render set is computed as one consistent result and applied atomically.

## Design

### 1. Render Snapshot Model

Introduce a `LifelogRenderSnapshot` value that contains the full derived render state needed by the map:

- cached path coordinates
- far route segments
- footprint runs
- selected-day center coordinate
- request metadata needed to decide whether content is current

The SwiftUI view reads this snapshot directly and stops rebuilding those values in computed properties.

### 2. Request-Driven Refresh

Introduce a lightweight request model capturing the inputs that affect rendering:

- selected day
- visible region / camera-derived LOD
- tile zoom and render budgets
- country ISO2 for map coordinate adaptation

Any relevant state change schedules a snapshot refresh instead of directly rebuilding coordinates in the view.

### 3. Async Build Pipeline

Refresh flow:

1. Main actor captures the current render request and cheap synchronous inputs.
2. Background work computes the heavy derived result:
   - unified fallback segments
   - far route runs and rendered segments
   - footprint runs
   - path cache
   - selected-day center
3. Main actor atomically swaps the snapshot once the request is still current.

### 4. Stale Result Protection

Use both cancellation and a generation token:

- cancel the previous render task when a new request supersedes it
- tag each request with a generation number
- discard results from older generations that finish late

This prevents:

- old day results replacing newer selections
- zoom-out results overwriting a newer zoom-in request
- stale fallback output briefly flashing after the user moves the map

### 5. View Behavior

The view keeps rendering the last good snapshot while a new one is building. That avoids blocking and avoids empty-state flashes during fast interactions.

Current-location dependent UI, like the robot marker and local footprint suppression around the avatar, remains live and continues to use current location state on the main actor.

## Testing Strategy

Add unit coverage around the extracted snapshot builder / coordinator behavior:

- near-mode snapshot prefers tile data and falls back to unified segments
- far-mode snapshot builds route segments once, outside the view body
- selected-day center derives from the same path snapshot
- stale generations are discarded so older async completions cannot overwrite newer requests

Compile/build verification remains necessary because the final integration point is SwiftUI view state.

## Risks

- `visibleRegion` can change rapidly, so refreshes must be coalesced enough to avoid task thrash
- keeping the old snapshot while refreshing can show slightly stale geometry briefly, but this is preferable to blocking or flashing empty content
- `LifelogView.swift` is already large, so the implementation should extract new snapshot types/helpers instead of adding more inline complexity
