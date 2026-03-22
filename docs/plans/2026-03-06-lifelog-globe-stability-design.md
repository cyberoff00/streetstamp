# Lifelog / Globe Stability and Fidelity Design

Date: 2026-03-06
Status: Approved
Owner: Codex + liuyang

## Background

Current behavior has four user-visible failures:

1. `Lifelog` and `GlobeView` can still stall as history grows.
2. `Lifelog` near-path rendering over-simplifies and visually straightens routes.
3. Route semantics are split across different read paths, so `Globe` can show data while `Lifelog` fails to surface the same history.
4. Rebuild / upgrade / user-scope recovery paths can leave data present on disk but not reachable in UI, including same-day mood state.

The target product behavior is closer to world-fog / Pikmin-style exploration: stable route coverage, no accidental segment joins, high-fidelity near-path footprints, and background battery usage that remains reasonable.

## Goals

- Make `Lifelog` and `GlobeView` consume one unified route semantics model.
- Prevent accidental line joins between unrelated route segments.
- Preserve higher path fidelity, especially in city-scale and near-field views.
- Render near-field `Lifelog` as footsteps along the true path instead of connected lines.
- Keep the app responsive while history grows and while the user is moving in foreground.
- Ensure upgrades, rebuilds, and user-scope recovery never make source data disappear from the UI.
- Treat same-day mood as durable user data, not expendable cache.
- Reduce passive logging battery cost through motion and accuracy gating.

## Non-Goals

- No visual redesign of existing map chrome, cards, or navigation.
- No database migration beyond current file-based storage.
- No attempt to preserve every derived cache across schema changes.

## Product Principles

1. Source of truth and render cache are separate concerns.
2. Derived render caches may be stale, partial, rebuilding, or discarded without losing user-visible history.
3. Upgrade safety is more important than cache reuse.
4. Route fidelity is preferred over aggressive simplification, but only within a bounded foreground-safe rendering budget.
5. Passive recording is state-machine driven; uncertain or stationary input should not become route data.

## Architecture

### 1. Truth Layers

- `JourneyStore` remains the authoritative source for journey tracks.
- `LifelogStore` remains the authoritative source for passive tracks and mood-by-day state.
- Mood persistence is treated as first-class user data and must be recovered with the same guarantees as route state.

### 2. Unified Render Event Stream

- Introduce a unified render provider that merges:
  - journey render events from `JourneyStore`
  - passive render events from `LifelogStore`
- Events remain tagged with `sourceType`, timestamp, and quality metadata.
- `Lifelog` and `GlobeView` both read from this unified stream.

### 3. Segment Builder

- Events are transformed into strict segments before any polyline or footprint rendering.
- Segments must break on:
  - source changes (`journey` <-> `passive`)
  - excessive time gaps
  - excessive spatial jumps
  - degraded / uncertain GPS quality
  - stationary-to-moving recovery
  - app lifecycle discontinuities that invalidate continuity assumptions
- No rendering path may reconnect segment boundaries.

### 4. Multi-LOD Rendering

- `GlobeView`
  - uses coarse LOD derived from the same segment set
  - optimized for far-view route coverage and stable interaction
- `Lifelog`
  - far / mid view uses shape-preserving segment geometry
  - near view uses footprint projection along true route distance
  - footprints never interpolate across segment boundaries

### 5. Derived Cache Model

- Tile manifests, day indexes, LOD products, and footprint projection caches are derived data only.
- They are versioned and may be rebuilt incrementally.
- UI read order:
  1. valid derived cache
  2. compatible older derived cache if still readable
  3. direct source-derived segments from the unified stream
- This guarantees "visible before optimized."

## Upgrade and Rebuild Strategy

### Rules

- Never treat cache invalidation as permission to hide source-backed user data.
- Never fail open to "empty state" when source files still decode.
- Never make a page depend solely on tile rebuild completion.

### Rebuild Model

- Use gradual cache regeneration instead of monolithic full rebuild.
- Prioritize:
  1. current user + today
  2. current viewport
  3. recent 7 days
  4. globe summary
  5. older historical days
- Use atomic cache replacement:
  - build into temporary artifacts
  - swap manifest/pointer only after successful completion

## Foreground Performance Strategy

- Main thread work must remain limited to:
  - point acceptance / rejection
  - lightweight observable state updates
  - schedule/coalesce render refreshes
- Heavy work moves off-thread:
  - segment building
  - tile updates
  - day index generation
  - footprint projection
  - historical rebuilds
- While the user is moving continuously in foreground:
  - only active-day, active-viewport, active-segment caches are updated eagerly
  - historical and off-screen rebuilds are deferred

## Passive Recording Strategy

### Motion States

- `moving`
- `stationary`
- `uncertain`

### Rules

- `moving`
  - can emit route points
  - still respects minimum distance and write coalescing
- `stationary`
  - updates current position state if needed
  - does not append route points
- `uncertain`
  - weak GPS / drift / impossible jumps
  - does not append route points
  - recovery into `moving` starts a new segment

### Expected Impact

- fewer drift spikes
- fewer stationary blobs
- fewer false joins
- lower background power draw

## Mood Durability

- Mood is not cache.
- Mood data must survive:
  - app rebuild
  - user-scope recovery
  - route file migration
  - partial cache invalidation
- Recovery / migration flows must copy or merge mood side-file data and embedded `moodByDay` payloads.

## Acceptance Criteria

### Correctness

- `Lifelog` and `GlobeView` show the same underlying history semantics.
- Segment boundaries never auto-connect.
- Upgrade / rebuild never causes source-backed history to disappear from the UI.
- Same-day mood survives rebuilds and user-scope recovery paths.

### Visual Fidelity

- Near-field `Lifelog` footprints follow the real path instead of simplified straight lines.
- Route turns and local shape are preserved substantially better than current behavior.

### Performance

- No obvious UI stalls while moving in foreground.
- Entering `Lifelog` and `GlobeView` remains responsive with historical data present.
- Cache rebuilds are user-invisible or limited to localized, non-blocking improvements.

### Battery

- Background passive mode target: under 10% battery over 12 hours in validation runs.
- This is a validation target, not assumed by implementation alone.

## Implementation Order

1. Source survivability and regression fixes
2. Unified render event stream
3. Strict segment builder
4. Lifelog / Globe render path unification
5. Passive motion and weak-GPS gating
6. Incremental cache rebuild prioritization
7. Performance and battery validation
