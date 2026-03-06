# CityCache + Lifelog Persistence Design

## Goal
- Ensure city cards always rebuild after journeys finish loading (including rebind/switch user).
- Replace per-point full-file lifelog rewrites with coalesced incremental persistence to reduce IO and battery impact.

## Scope
- In scope:
  - `CityCache` load-order correctness tied to `JourneyStore.hasLoaded` transitions.
  - `LifelogStore` persistence strategy: append incremental points and debounce/snapshot writes.
- Out of scope:
  - Changing lifelog rendering output semantics.
  - Data model redesign for journeys/tiles.

## Design Decisions
1. `CityCache` subscribes to `journeyStore.$hasLoaded` and runs `rebuildFromJourneyStore()` on `true`.
2. `CityCache.rebind()` avoids one-shot blind rebuild; relies on same subscription signal.
3. `LifelogStore` writes newly-ingested points to a delta log (`.jsonl`) and debounces full payload snapshot.
4. Full snapshot still happens on lifecycle boundaries (`background/inactive`) via explicit flush API.

## Data Flow
- Ingest point -> append to in-memory arrays -> append delta line -> schedule debounced snapshot.
- Load store -> load snapshot -> replay delta lines -> clear delta on successful snapshot flush.

## Risks / Mitigations
- Risk: duplicate points when replaying delta.
  - Mitigation: existing dedupe check by coordinate equality before append.
- Risk: stale city cache after rapid user switches.
  - Mitigation: reset rebuild guard on `hasLoaded=false`, rebuild on next `true`.

## Verification
- Unit tests for:
  - CityCache rebuild triggered by `hasLoaded=true`.
  - Lifelog coalescing: multiple ingests trigger limited snapshot writes and preserve loaded coordinates.
