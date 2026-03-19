# MapView Signal Gap Dashed Design

**Goal:** Make `MapView` show dashed route connections when live tracking clearly experiences a signal interruption and then recovers, without changing the existing real-time rendering architecture.

## Current State

`MapView` already knows how to render dashed segments. In [`StreetStamps/MapView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/MapView.swift), the overlay renderer applies `lineDashPattern` whenever a route segment is marked as a gap. The missing behavior is upstream: `TrackingService` is conservative about when it marks a live connection as `.dashed`, so some real recovery jumps never reach the renderer as gap segments.

## Problem

When the device loses location signal for a meaningful period and later regains a trustworthy fix, the app may reconnect the route as a normal solid segment or omit a visible bridge entirely. This makes the live map harder to read because users cannot tell where tracking was continuous versus interrupted.

## Recommended Approach

Keep `MapView` unchanged and enhance `TrackingService` gap classification.

This preserves the existing flow:

1. `TrackingService` ingests live location updates.
2. It classifies each new connection as solid or dashed.
3. It publishes `renderUnifiedSegmentsForMap`.
4. `MapView` renders those segments with its existing solid/dashed styling.

## Design

### 1. Add a recovery-oriented interruption rule

Inside `TrackingService.ingest(_:)`, introduce a dedicated branch for signal recovery.

This branch should identify cases where:

- recent updates were weak, rejected, or absent for long enough to imply interruption
- the new accepted point is trustworthy enough to use
- the distance from the last stable anchor is large enough to imply reconnection rather than tiny drift

When that branch matches, the new connection should be classified as `isGapLike = true`, and when appropriate also as a missing connection segment.

### 2. Keep existing anti-noise protections

The feature must not create dashed "confetti" during ordinary walking or indoor jitter. The current protections remain important:

- do not mark a gap when elapsed time is long but movement is negligible
- do not mark a gap for weak-accuracy micro-jumps
- continue dropping clearly implausible drift unless the recovery heuristics indicate a meaningful reconnection

### 3. Limit scope to live MapView behavior

Do not change:

- `MapView` renderer widths or dash styling
- `SharingCard` route segmentation
- `CityDeepView` or detail map rendering
- the shared static route segmentation pipeline in `RouteRenderingPipeline`

This keeps the change narrowly focused on real-time tracking recovery.

## Expected User Outcome

Users should start seeing a thin dashed bridge in `MapView` after real interruptions such as:

- subway or tunnel exits
- entering and leaving buildings or parking structures
- brief GPS loss followed by a meaningful relocation

Users should not start seeing dashed segments for:

- standing still with delayed updates
- ordinary city walking with weak but continuous GPS
- tiny recovery hops after jitter

## Testing Strategy

Add focused tests around `TrackingService` publication of `renderUnifiedSegmentsForMap`:

- interrupted tracking followed by recovery produces at least one `.dashed` segment
- long delay with minimal movement stays solid or produces no gap
- weak jitter does not create dashed segments
- existing large missing/migration scenarios still produce dashed segments

## Risks

- If thresholds are too loose, normal movement may be misread as interruption.
- If thresholds remain too strict, the change will be invisible in practice.

The implementation should therefore favor a small heuristic addition with explicit tests around borderline cases.
