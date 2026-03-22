# Incremental City Cache And Cloud Sync Design

**Problem**

The app currently pays increasing runtime cost as local journey volume grows:

- `CityCache.rebuildFromJourneyStore()` recomputes city cards by scanning all completed journeys.
- `JourneyCloudMigrationService.migrateAll(...)` rebuilds upload payloads by scanning all shareable journeys.

This creates avoidable work on user-facing flows such as finishing a journey, changing visibility, opening collection surfaces, and foreground sync.

**Goals**

- Remove full-journey scans from normal interactive flows.
- Keep UI responsive as journey count grows.
- Preserve eventual correctness with background repair paths.
- Keep manual repair and full rebuild options for recovery/debugging.

**Non-Goals**

- Redesigning the local `local_*` profile model.
- Changing backend schema for public journey visibility semantics.
- Building multi-profile local storage on one device.

## Approach

Replace the two full-scan workflows with event-driven incremental state:

1. `CityCache` maintains a persistent membership index keyed by `journeyID`.
2. Cloud sync maintains a persistent dirty queue keyed by `journeyID`.
3. Foreground flows enqueue or apply narrow updates for the touched journey only.
4. Cold start and settings retain explicit repair hooks for background/full reconciliation.

## City Cache Design

### New Persistent Index

Add a cache-side index file, for example:

- `Application Support/StreetStamps/<localID>/Caches/city_membership_index.json`

Each entry stores the minimum state needed to reverse and reapply a journey's city contribution:

- `journeyID`
- `cityKey`
- `cityName`
- `countryISO2`
- `memoryCount`
- `isCompleted`
- `updatedAt`

### Normal Update Flow

When a journey changes, compute its current contribution and compare against the stored index entry:

- New completed journey:
  - add its counts to one city card
  - store index entry
- Journey deleted:
  - remove prior contribution from old city card
  - drop index entry
- Journey city changed:
  - subtract old contribution
  - add new contribution
  - rewrite index entry
- Journey memory count changed:
  - update only the affected city's memory total

This turns city card maintenance into O(1) or O(log n) work relative to touched entities, instead of O(total journeys).

### Fallback / Repair

Keep `rebuildFromJourneyStore()` but demote it to:

- first-run index migration
- explicit repair action in settings/debug tools
- background recovery when index is missing/corrupt

Interactive surfaces should no longer call it from `onAppear`.

## Cloud Sync Design

### New Persistent Queue

Add a local queue file, for example:

- `Application Support/StreetStamps/<localID>/Caches/pending_cloud_sync.json`

Each queued record stores:

- `journeyID`
- `operation` (`upsert` or `delete`)
- `lastLocalUpdatedAt`
- `retryCount`
- `lastError`
- `enqueuedAt`

### Queue Producers

Enqueue only the touched journey when one of these happens:

- a completed journey becomes shareable (`friendsOnly` / `public`)
- a shareable journey is edited
- a shareable journey is deleted
- a shareable journey becomes `private` and must be removed remotely

Private journeys never enter upload payload generation unless they transition out of private.

### Queue Consumer

Add a background flush worker triggered by:

- app launch after stores are loaded
- auth becomes available
- app foreground
- explicit retry in settings

Worker behavior:

- process small batches
- upload only queued `upsert` journeys
- send explicit deletes for queued `delete` items
- remove successful items
- apply retry backoff for failures
- pause when no token is available

### Fallback / Repair

Retain a full reconcile path, but make it:

- manual from settings/debug
- optional background repair if queue metadata is obviously inconsistent

Normal save flows should not invoke `migrateAll()` on the full local dataset.

## User Experience Impact

- Finishing one public/friends-only journey only syncs that journey.
- Opening collection/city surfaces does not trigger a full city rebuild.
- Large local history grows storage, but not the per-action scan cost.
- If the app crashes mid-sync, pending items survive restart and retry later.

## Risks

- Incremental indexes can drift if a write path forgets to emit an update.
- Queue compaction must collapse repeated updates to the same `journeyID`.
- Old code paths that still call full rebuild/sync may hide regressions and need explicit cleanup.

## Mitigations

- Add narrow tests for create/edit/delete/visibility transitions.
- Keep full rebuild as a validation tool.
- Add lightweight integrity checks at launch:
  - missing index file
  - malformed queue items
  - queue references to missing local journeys

## Success Criteria

- No normal `onAppear` path calls `cityCache.rebuildFromJourneyStore()`.
- No normal journey save path calls full `migrateAll()` for the entire store.
- Adding or editing one journey touches one index entry and one queue entry.
- Existing local and cloud-visible behavior remains functionally equivalent.
