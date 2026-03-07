# Lifelog High-Quality Cache Design

Date: 2026-03-07
Status: Approved
Owner: Codex + liuyang

## Background

`Lifelog` currently mixes multiple render sources and fallback qualities:

- tile-backed segmented routes
- passive polyline fallback
- near-mode footprints derived from a different path shape than far-mode routes

This causes three visible problems:

- low-quality route regressions after day switches or viewport changes
- accidental visual closure / segment bridging
- near / far mode inconsistency because the two modes do not share one segmented source of truth

The page also needs to stay responsive while users move, switch days, or zoom, and the app should warm recent days before the user opens `Lifelog`.

## Goal

Build a high-quality, segmented render cache for `Lifelog` that:

- only renders high-quality segmented results
- never downgrades an existing high-quality result to a lower-quality fallback
- uses one segmented track model for both far-route lines and near-footprint markers
- avoids `loading` and avoids showing stale-day content when a day has no cache yet
- warms the most recent 7 days in the background without hurting foreground performance

## Non-Goals

- no redesign of the `Lifelog` UI
- no persistent disk cache format changes in this task
- no attempt to make today update more frequently than the approved 5 second window
- no globe rendering redesign in this task

## Source Of Truth

The source of truth becomes a single high-quality segmented day snapshot:

- one day
- one country coordinate adaptation context
- one pair of source revisions (`journeyRevision`, `lifelogRevision`)
- one ordered list of segments with preserved boundaries

The cache must never flatten a day's geometry into one full-day polyline for rendering. Segment boundaries remain explicit across:

- source changes
- large movement gaps
- day boundaries

## Design

### 1. Segmented Day Snapshot

Introduce an in-memory `SegmentedTrackSnapshot` for one day. It stores:

- cache key (`day`, `countryISO2`, revisions)
- all day tile-backed `TrackTileSegment` values for that day
- ordered high-quality coordinate runs per segment
- stable center coordinate for selected-day recentering

This is the only geometry source used by both far and near render modes.

### 2. Viewport Render Cache

Introduce a derived viewport cache keyed by:

- day snapshot key
- viewport bucket
- render LOD
- render mode

This cache stores ready-to-render values such as:

- far route segments
- footprint runs
- selected-day center coordinate

Viewport cache entries are always derived from one segmented day snapshot. They never come from a lower-quality fallback.

### 3. One Geometry Model, Two UI Modes

Far mode and near mode must render from the same segmented runs:

- far mode: convert segmented runs into route line segments
- near mode: sample footprints from the exact same segmented runs

Result: near / far mode differ only in presentation, not in geometry semantics.

### 4. No-Downgrade Policy

Rules:

- if the current screen already has a high-quality render snapshot, viewport changes must keep showing it until a newer high-quality result is ready
- low-quality passive fallback must not replace a high-quality result
- switching to a day with no cached high-quality snapshot shows only the base map until a high-quality snapshot is ready

This preserves visual stability without showing stale-day content or loading spinners.

### 5. Background Warmup

The app warms only day snapshots, not viewport-specific entries.

Warmup order:

1. today
2. yesterday
3. the previous 5 days

Warmup constraints:

- low priority
- cancellable
- preempted by explicit `Lifelog` interactions
- no main-thread heavy work

### 6. Today Refresh Policy

Today is the only day that grows continuously while the user moves.

Rules:

- `trackTileRevision` changes only mark `today` dirty
- a 5 second coalescing task starts only when a new revision arrives
- no polling when nothing changed
- when the task fires:
  - if revisions did not change, do nothing
  - if tail-only incremental append is safe, extend or append the last segment
  - otherwise rebuild today's high-quality day snapshot

This keeps today responsive without thrashing the cache during movement.

### 7. Incremental Append Constraints

Today may use tail-only incremental append when all are true:

- same day
- newer revision only
- new points start after the last cached timestamp
- no source change boundary
- no large gap boundary
- no country adaptation change

If any condition fails, rebuild today's full day snapshot instead of guessing.

### 8. Cache Lifetime

- day snapshot cache retains only the newest 7 days
- viewport cache is LRU and small
- revision mismatch invalidates affected entries
- country ISO2 change invalidates entries built for the old mapping context

## Testing Strategy

Add pure logic coverage for:

- warmup ordering and 7 day cap
- no-downgrade apply decisions
- viewport key bucketing
- segmented render derivation preserving run boundaries
- today incremental append refusing unsafe merges

Build verification remains necessary because final integration touches SwiftUI state and app startup tasks.

## Risks

- day snapshot cache misses will intentionally show only the base map until high-quality data arrives
- incremental append logic must be conservative; false positives would reintroduce accidental route closure
- warmup must yield to user-driven work or it will compete with other screens
