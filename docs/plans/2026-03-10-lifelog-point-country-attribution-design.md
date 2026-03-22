# Lifelog Point Country Attribution Design

**Scope:** Ship a China-friendly post-launch path for new lifelog passive data by attributing country at the point level without adding noticeable foreground tracking cost.

## Goals

- Make new passive lifelog and globe rendering accurate for Mainland China by applying GCJ only to confirmed China portions of a path.
- Avoid blocking the foreground location ingestion path with reverse geocoding or any other expensive country-resolution work.
- Preserve raw WGS84 points as the source of truth and build country attribution as rebuildable sidecar indexes.
- Support mixed-country paths in a single day or segment so China and non-China portions render independently.

## Non-Goals

- Do not backfill historical passive data for the initial rollout.
- Do not change journey-specific country attribution in this phase.
- Do not rely on coarse bbox guesses as the final product decision for GCJ rendering.

## Current Problem

- Passive points currently store only `lat/lon/timestamp`, so they carry no per-point or per-segment country metadata.
- Lifelog and globe rendering currently consume a single `countryISO2` value for an entire render request, which can misclassify mixed-country passive data.
- `LocationHub` still exposes a fast China bbox guess, which is acceptable as a scheduling hint but not as the final signal for GCJ conversion.

## Design Summary

- Keep passive point ingestion cheap: append the raw point plus a lightweight spatial cell identifier.
- Resolve country attribution asynchronously per cell, not per point.
- Build a point-country sidecar index and compress it into country runs for rendering.
- Render WGS84 runs unchanged unless the run has a confirmed `iso2 == "CN"`.
- Treat unresolved points as `unknown` and render them as WGS84 until a confirmed country arrives.

## Architecture

### 1. Raw Passive Point Storage

Extend new passive point records with a deterministic `cellID` computed locally in O(1) time from latitude and longitude. The raw passive store remains the immutable source of truth:

- `pointID`
- `timestamp`
- `lat`
- `lon`
- `accuracy`
- `cellID`

`cellID` must be cheap to compute and stable enough for cache reuse. A fixed-size grid key is sufficient for this phase; the exact quantization can be chosen during implementation.

### 2. Cell Country Cache

Add a rebuildable sidecar store keyed by `cellID`:

- `cellID`
- `resolvedISO2`
- `source`
- `confidence`
- `resolvedAt`

This cache is filled asynchronously. One resolved cell is reused by all future points in the same cell, which keeps geocoder usage proportional to explored area instead of point count.

### 3. Point Country Index

Add a second sidecar index keyed by `pointID`:

- `pointID`
- `resolvedISO2?`

This decouples raw point persistence from attribution updates. We can rebuild this index whenever the cell cache changes without mutating the original raw point file.

### 4. Country Segment Index

Add a render-oriented compressed representation:

- `segmentID`
- `startPointID`
- `endPointID`
- `resolvedISO2?`

Adjacent points with the same resolved country collapse into a single run. Rendering will consume these runs directly instead of applying one country to the whole request.

## Data Flow

### Foreground Path

Foreground ingestion must stay lightweight:

1. Accept a new passive location after the existing distance and accuracy gates.
2. Compute `cellID`.
3. Append the point record.
4. Schedule background attribution work.

No reverse geocoding, no GCJ conversion, and no point-country rebuilding should happen inline with the ingestion call.

### Background Attribution Path

Background work resolves only new or stale cells:

1. Read newly appended points and collect unresolved `cellID`s.
2. Deduplicate `cellID`s.
3. Resolve country per cell through the authoritative geocode/canonical pipeline.
4. Persist `cellCountryCache`.
5. Map affected points to `resolvedISO2`.
6. Incrementally rebuild the tail of `countrySegments`.
7. Notify render caches that attribution changed.

The background worker should be serialized or low-concurrency to respect geocoder rate limits.

## Country Resolution Rules

### Final Rendering Signal

Only confirmed country attribution may drive GCJ:

- `resolvedISO2 == "CN"` -> convert that run to GCJ-02
- anything else -> keep WGS84

### Allowed Inputs

Use authoritative signals in this order:

1. canonical reverse geocode / placemark `isoCountryCode`
2. canonical city key suffix `|ISO2`
3. unresolved (`unknown`)

### Explicitly Forbidden

- Do not use coarse China bbox checks as the final decision for GCJ rendering.
- Do not use the current global `lifelogStore.countryISO2` to reinterpret historical passive points.

## Rendering Changes

### Lifelog

- Replace whole-request `countryISO2` rendering with country-aware runs derived from the sidecar indexes.
- Build far-route groups and footprint groups from country-specific runs.
- Convert only the confirmed China runs through `MapCoordAdapter` / `ChinaCoordinateTransform`.

### Globe

- Convert passive tile segments into country-aware route runs before passing them into the globe route rendering pipeline.
- Preserve mixed-country route behavior so only China portions receive GCJ conversion.

## Performance Strategy

- Frontground writes remain O(1) append operations plus local `cellID` calculation.
- Country attribution reuses the cell cache, so repeated movement inside the same area has near-zero country-resolution cost.
- Segment rebuilding is incremental and tail-oriented instead of full-day recomputation.
- Render paths remain synchronous but consume precomputed indexes rather than geocoding or resolving country on demand.

## Failure Handling

- If country resolution is unavailable or throttled, keep affected points as `unknown`.
- `unknown` points render in WGS84 and remain eligible for later background enrichment.
- Sidecar index corruption should be recoverable by deleting and rebuilding indexes from raw passive points.

## Rollout Plan

### Phase 1

- Introduce sidecar schemas and point `cellID`.
- Stop allowing bbox-only country signals to drive GCJ.
- Build country-aware passive rendering for newly collected data only.

### Phase 2

- Optimize incremental rebuild costs.
- Add tooling to inspect attribution coverage and cache hit rates.

### Phase 3

- Optional historical backfill for old passive data.

## Risks

- Cell size that is too coarse could blur border behavior; too fine could increase geocoder churn. This needs calibration during implementation.
- Background attribution lag means a newly collected China point may briefly render as WGS84 until the cell is confirmed.
- Rebuildable sidecar indexes add complexity, so versioning and corruption recovery need explicit tests.

## Success Criteria

- New passive points collected after rollout do not trigger noticeable foreground slowdowns.
- Mixed-country passive paths render with GCJ applied only to confirmed China portions.
- Reverse-geocode volume scales with newly visited cells, not raw point count.
- Lifelog and globe no longer depend on one global passive country value to render all passive history.
