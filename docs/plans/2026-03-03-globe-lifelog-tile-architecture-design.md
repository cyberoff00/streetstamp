# Globe/Lifelog Tile Architecture Design (Journey + Passive)

Date: 2026-03-03
Status: Approved
Owner: Codex + liuyang

## 1. Background and Problem

Current behavior mixes two concerns:
- Journey has its own authoritative storage under `Journeys/`.
- Lifelog also stores passive points and (via backfill) journey points in `Caches/lifelog_route.json`.

This causes:
- duplicated storage of journey tracks,
- consistency complexity,
- first-open Globe lag from repeated full-history segmentation and rendering prep.

## 2. Goals

- Keep one authoritative journey source.
- Keep one authoritative passive lifelog source.
- Build Globe and Lifelog rendering from those two sources through a tile index database.
- Preserve current Globe visual behavior:
  - far-view country rendering,
  - city highlight,
  - near-view routes.
- Avoid carrying forward legacy lifelog history from old `lifelog_route.json`.

## 3. Non-Goals

- No visual redesign (colors/opacity/thresholds remain unchanged).
- No full domain rewrite of Journey model.
- No migration of legacy lifelog historical points into the new passive store.

## 4. Target Architecture

### 4.1 Authoritative data sources

1. `JourneyStore` (source A)
- remains the sole truth for journey lifecycle and journey tracks.
- no longer backfills journey coordinates into lifelog storage.

2. `PassiveLifelogStore` (source B)
- stores only passive points collected when tracking is not active.
- new file: `Caches/lifelog_passive_route.json`.

### 4.2 Rendering index layer

3. `TrackTileStore` (new rendering index)
- input: source A + source B.
- output: precomputed tiled route/index data for Globe and Lifelog.
- both Globe and Lifelog read this layer for map rendering.

## 5. Storage Layout

User root: `Application Support/StreetStamps/<userID>/`

- `Journeys/` (existing)
- `Caches/lifelog_passive_route.json` (new passive-only source)
- `Caches/track_tiles/manifest.json` (new)
- `Caches/track_tiles/z{z}/x{x}/y{y}.tile.json` (new)

`manifest.json` fields:
- `schemaVersion`
- `sourceRevision` (`journeyRevision`, `passiveRevision`)
- `builtAt`
- `zoomLevels`
- `bounds`
- `statsSummary`

## 6. Migration Strategy

User decision: legacy lifelog handling option A.

On first run after upgrade:
1. Check migration marker (e.g. `.migrated_vX_track_tiles`).
2. Rename legacy `Caches/lifelog_route.json` to `Caches/lifelog_route.json.bak`.
3. Create empty `Caches/lifelog_passive_route.json`.
4. Build initial track tiles from `Journeys/` only.
5. Write migration marker.

After migration:
- legacy file is never read by runtime paths.
- passive data starts accumulating from post-upgrade events only.

## 7. Rendering Pipeline

### 7.1 Read path

Globe and Lifelog map rendering should:
- query visible tiles by current zoom/viewport,
- load precomputed segments from `TrackTileStore`,
- render without full-history in-memory route reconstruction.

### 7.2 Update path

- New passive point -> update affected tiles incrementally.
- Journey finalized/edited -> update impacted tiles incrementally.
- Revision mismatch -> incremental rebuild from changed ranges, not full sync by default.

### 7.3 Camera/bootstrap

- Use `manifest.bounds` for initial fit/camera hints.
- Avoid full coordinate scans on first open.

## 8. Compatibility with Existing Globe Visual Layers

Preserved as-is:
- country glow/fill/border behavior,
- city highlight behavior,
- route near-view styling behavior.

Only data provider changes from direct full-route arrays to tile-index output.

## 9. Performance Expectations

- Warm open: map becomes interactive quickly by loading disk tiles directly.
- Cold/no-tile open: UI remains responsive while tile build runs in background.
- Removal of repeated full scans should eliminate current first-open lag spikes.

## 10. Testing and Acceptance Criteria

1. Performance
- Warm-open Globe interaction target: < 500 ms to responsive map surface.
- No obvious main-thread stutter during first screen paint.

2. Data correctness
- Journey history visible from journey source via tiles.
- Passive source includes only post-upgrade passive points.
- legacy `lifelog_route.json` migrated to `.bak` and not consumed.

3. Visual regression
- Far country render, city highlight, near route style unchanged.

4. Stability
- App restart still loads from disk tiles.
- User switch keeps strict per-user isolation.

## 11. Risks and Mitigations

- Risk: tile schema iteration churn.
  - Mitigation: explicit `schemaVersion`, deterministic full rebuild on schema bump.

- Risk: migration edge cases for corrupted legacy files.
  - Mitigation: best-effort rename with fallback logging; continue with empty passive store.

- Risk: index drift from source updates.
  - Mitigation: revision checks + incremental rebuild hooks on both source streams.

## 12. Rollout Plan

1. Ship storage split + migration.
2. Ship `TrackTileStore` build/read path behind a runtime flag if needed.
3. Switch Globe and Lifelog map read path to tile source.
4. Remove legacy backfill dependency after validation.

