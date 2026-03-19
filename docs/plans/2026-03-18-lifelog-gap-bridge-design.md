# Lifelog Gap Bridge Design

## Background

`Lifelog` currently breaks passive history into separate render runs when the unified track pipeline detects a source change, a large time gap, or a large spatial jump. Once that happens, the affected views render those runs as disconnected pieces.

That is safe, but it makes ordinary passive dropouts feel like missing route chunks. The desired product behavior is closer to a "flight path" metaphor: keep true recorded segments visually intact, and bridge only the exact automatic break between adjacent runs using a dashed line.

## Goal

When `Lifelog` contains an automatically broken gap, render a dashed bridge from the previous run's last point to the next run's first point.

## Confirmed Product Rules

- Only connect two runs that are adjacent in time order.
- The bridge must connect exactly:
  - previous run last point
  - next run first point
- Do not search for a "better" nearby point.
- Do not connect non-adjacent runs.
- Do not auto-close loops by connecting the route start and end.
- Very large gaps should still render as dashed bridges if they are adjacent.
- The bridge should look identical to the solid route in every respect except line style:
  - same color
  - same width
  - same halo/glow treatment
  - same surface-specific coordinate adaptation
  - only the dash pattern differs

## Non-Goals

- Do not change passive collection policy.
- Do not add inferred intermediate geometry or synthetic sampled points.
- Do not change `Journey` live-tracking segmentation in this scope.
- Do not change map tile persistence semantics in this scope.

## Approach Comparison

### A. Bridge in render snapshots (selected)

Add dashed bridge segments after segmented day runs are built for `Lifelog`, using only adjacent runs in sorted order.

Pros:
- Keeps source data unchanged.
- Keeps bridge behavior scoped to `Lifelog`.
- Reuses existing `RenderRouteSegment.Style.dashed` styling pipeline.
- Easy to guarantee "adjacent only" semantics.

Cons:
- Needs snapshot/render-group changes instead of reusing raw tile segments directly.

### B. Encode bridges as synthetic `TrackTileSegment`s

Create synthetic gap segments earlier in the unified track/tile pipeline.

Pros:
- More globally reusable.

Cons:
- Pollutes source-derived segment sets with presentation-only data.
- Higher risk of affecting globe/tile/cache behavior unexpectedly.

### C. Interpolate directly in footprint sampling

Have the footprint sampler jump across gaps and render a dashed path there.

Pros:
- Very local to one view.

Cons:
- Does not solve far-route rendering.
- Splits gap semantics across multiple render paths.

## Selected Design

### 1. Introduce explicit adjacent-run bridge generation

When `LifelogRenderSnapshotBuilder` has finished producing ordered render runs for a selected day, compute bridges by iterating adjacent run pairs:

- pair run `i` with run `i + 1`
- if both runs have at least one coordinate, create a bridge segment
- bridge coordinates are exactly `[runA.last, runB.first]`

No other pairings are allowed.

### 2. Treat bridges as presentation-only dashed segments

The bridge exists only in the final render snapshot output. It is not written back into:

- `LifelogStore`
- unified render events
- tile manifests
- country attribution data

This preserves truth-vs-render separation.

### 3. Match solid-route styling except for dash pattern

Bridges should flow through the same route rendering path as other segments so they inherit:

- normal halo/core stroke treatment
- line widths
- color and opacity rules
- country-specific coordinate adaptation

The only difference is `style == .dashed`.

### 4. Preserve current run boundaries

The bridge visually connects two runs, but those runs remain distinct for logic purposes:

- footprint groups remain separate
- future filtering still sees two runs
- no merge of source coordinates

This keeps the product visually connected without pretending the missing portion is real recorded track.

## Data Flow

1. Unified segment builder breaks the day into ordered `TrackTileSegment`s.
2. `LifelogRenderSnapshotBuilder.makeRenderRuns` converts those into ordered render runs.
3. New bridge builder inspects adjacent runs and creates dashed bridge segments.
4. Final `LifelogSegmentedRenderGroup` / `LifelogRenderSnapshot` output appends those dashed bridge segments alongside normal far-route segments.
5. `Lifelog` views render the combined segment list, so the gap reads as a flight-like dashed connection.

## Error Handling And Edge Cases

- If either adjacent run is empty, emit no bridge.
- If a run has one point only, it may still participate in a bridge using that lone point.
- If start and end coordinates are identical, skip the bridge because it adds no visual meaning.
- If the selected day contains only one run, emit no bridges.
- Cross-city or cross-country adjacent runs are still bridged, by product decision.

## Testing Strategy

Add focused tests that verify:

- adjacent runs create exactly one dashed bridge
- non-adjacent runs do not get connected
- a looped route does not auto-connect start to end
- bridge styling differs only by dashed style, not by geometry or surface adaptation path
- very large adjacent gaps still produce dashed bridges

## Risks

- Users may read the bridge as "travel happened here" rather than "data was missing here."
  - Accepted intentionally: this is the requested flight-like metaphor.
- If bridges are inserted too early in the pipeline, caches and downstream consumers may treat them as truth.
  - Mitigation: keep them render-only.

## Acceptance Criteria

- `Lifelog` visually bridges automatic adjacent gaps with dashed lines.
- The bridge always connects only the previous run end and next run start.
- Route start and route end never auto-connect unless they are truly adjacent runs.
- Large adjacent gaps still render as dashed bridges.
- Bridge appearance matches solid route appearance except for the dash pattern.
