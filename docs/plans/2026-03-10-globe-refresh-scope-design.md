# Globe Refresh Scope Design

**Goal:** Restrict Globe refresh behavior to explicit business events instead of passive state fan-out.

**Approved Refresh Triggers**

- Refresh when a Globe page instance appears for the first time.
- Refresh after a journey is saved or ended successfully.
- Refresh after passive lifelog finishes a day rollover and persists the new day boundary state.

**Out of Scope**

- No live refresh from location updates.
- No refresh from `trackTileRevision`, `refreshRevision`, cached city counts, or other low-level store changes.
- No change to globe rendering results or route selection logic.

**Design**

Introduce a dedicated Globe refresh event coordinator. Business logic emits a refresh event only at the three approved trigger points. `GlobeViewScreen` listens to that single event source and rebuilds its render snapshot when needed. `MapboxGlobeView` becomes a rendering surface for prepared data and stops observing upstream change tokens.

This separates business refresh policy from rendering implementation:

- Stores and finalization flows decide *when* Globe should refresh.
- `GlobeViewScreen` decides *how* to rebuild the prepared globe snapshot.
- `MapboxGlobeView` only decides *how* to draw the snapshot.

**Why This Approach**

- Matches the approved product behavior exactly.
- Removes duplicate refresh chains across `GlobeViewScreen` and `MapboxGlobeView`.
- Prevents simulator-only LLDB degradation caused by high-frequency debug-time redraws and logging.
- Keeps future refresh changes explicit and testable.

**Trigger Mapping**

- Globe first enter: refresh inside the page's initial task/on-appear path.
- Journey save/end: emit after completed-journey persistence is accepted by `JourneyStore`.
- Passive lifelog day end: emit only when passive points cross into a new calendar day and the store commits that transition.

**Testing Strategy**

- Unit test the coordinator event revision API.
- Unit test that journey completion emits a Globe refresh event.
- Unit test that passive lifelog emits only on day rollover, not on same-day appends.
- Keep existing globe route resolution tests unchanged.
