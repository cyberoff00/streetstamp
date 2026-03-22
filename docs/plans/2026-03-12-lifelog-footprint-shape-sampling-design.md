# Lifelog Footprint Shape Sampling Design

Date: 2026-03-12
Status: Approved
Owner: Codex + liuyang

## Background

`Lifelog` near-mode footprints currently come from a fixed-distance sampler in `StreetStamps/LifelogView.swift`.

The current pipeline does two things well:

- samples by traveled distance instead of raw GPS point count
- avoids obvious marker overlap with a viewport-aware planner

But it still produces a visual result that feels too mechanical for the desired "Pikmin-like" effect:

- dense city blocks and loops can still look cluttered
- long straight stretches get over-populated with repetitive markers
- important route bends are not explicitly preserved as visual anchors
- the final look reads as "points placed along a route" instead of "footprints expressing the route's overall shape"

## Goal

Keep the existing near / far mode architecture, but change near-mode footprint generation so that it:

- preserves the overall silhouette of a day's route
- keeps turn points visually legible
- reduces clutter in dense local movement
- avoids filling every visible stretch with evenly spaced footsteps
- still feels like a walked path instead of a decorative icon trail

## Non-Goals

- no redesign of the `Lifelog` UI chrome
- no change to far-mode route rendering semantics
- no globe rendering changes
- no persistent cache format changes
- no attempt to make footprint density fully screen-space driven in this task

## Problem Statement

The current sampler is shape-agnostic. It only knows:

- total path order
- fixed spacing (`50m`)
- hard breaks over large jumps (`8000m`)

That makes the visual density depend mostly on route length, not on route importance.

As a result:

- a meaningful turn and a trivial intermediate point are treated equally
- a long straight street can dominate the map with unnecessary footsteps
- complex local traces can remain noisy even after viewport-level decimation

The viewport planner in `StreetStamps/LifelogFootprintRenderPlanner.swift` is currently doing too much of the visual cleanup. It is good as a last-stage anti-collision layer, but it should not be responsible for deciding the route's visual shape.

## Design

### 1. Two-Stage Footprint Sampling

Replace the current fixed-distance-only sampler with a two-stage pipeline:

1. **Shape anchor extraction**
2. **Rhythm fill between anchors**

This keeps the route recognizable before viewport clipping and marker culling happen.

### 2. Shape Anchor Extraction

For each footprint run:

- always keep the first and last point
- keep points where the heading change exceeds a turn threshold
- keep points that cap an overlong straight segment
- preserve explicit run boundaries and gap breaks

The anchor extractor should operate on geographic coordinates before MapKit coordinate adaptation, so it stays aligned with the existing route segmentation logic.

Recommended initial thresholds:

- turn threshold: about `24°`
- maximum straight span without an anchor: `140m`
- minimum segment length worth filling later: `90m`

Effect:

- bends survive aggressive thinning
- route outer shape stays legible
- straight corridors become naturally sparse

### 3. Rhythm Fill Between Anchors

After anchors are chosen, optionally add a small number of intermediate footsteps between anchor pairs:

- very short spans: add none
- medium spans: add `1`
- long spans: add `2-3`
- never exceed a fixed per-segment cap

The fill rule should be intentionally conservative. This is not a return to uniform spacing. The job is to preserve walking rhythm, not to repaint the full polyline.

Recommended initial behavior:

- shorter than `90m`: `0` fill points
- `90m...180m`: `1` fill point
- `180m...320m`: `2` fill points
- above `320m`: `3` fill points max

### 4. Keep Viewport Planner As Final Anti-Collision Layer

`StreetStamps/LifelogFootprintRenderPlanner.swift` should remain the last-stage planner that:

- clips to buffered viewport ranges
- removes markers near the avatar / current location
- enforces a screen-local minimum separation
- limits overall marker count by LOD

But after this redesign, that planner should be tuning and collision control, not the primary source of shape simplification.

### 5. Preserve Existing Render Contracts

The redesign keeps current contracts intact:

- near mode still renders footprint markers
- far mode still renders route segments
- the same segmented day snapshot remains the shared geometry source
- large route jumps still break instead of creating fake continuous walking

This limits integration risk and keeps the change local to footprint derivation.

## Implementation Shape

### Sampling API

Introduce a shape-aware sampler helper, likely by expanding or replacing `LifelogFootprintSampler`, with responsibilities split into:

- anchor extraction from a raw run
- bounded fill point generation between anchor pairs
- final deduplication / boundary preservation

The top-level call site in `StreetStamps/LifelogRenderSnapshot.swift` continues to request one footprint run per segmented route run.

### Data Flow

Current:

`raw run -> fixed 50m sampler -> map coordinate adaptation -> viewport planner`

Proposed:

`raw run -> shape anchors -> bounded rhythm fill -> map coordinate adaptation -> viewport planner`

### Tuning Surface

Keep the first version parameterized through constants in code, not user settings.

That keeps experimentation cheap while avoiding premature settings sprawl.

## Testing Strategy

Add focused unit coverage for the shape-aware sampler:

- preserves first / last points
- preserves meaningful turns
- does not overfill long straight runs
- never samples across a large gap break
- keeps loops recognizable without reproducing all raw points

Add planner-level coverage only where necessary to confirm the new sampler still works with the existing viewport decimation layer.

## Risks

- too many anchors will make the result regress toward the current cluttered look
- too few anchors will make the path feel decorative instead of lived-in
- turn thresholds that are too low will preserve noise from GPS jitter
- turn thresholds that are too high will erase the silhouette of tighter urban movement

The first implementation should therefore bias slightly toward sparseness, then tune upward only where route shape is visibly lost.
