# CloudKit Incremental Sync Design

**Goal:** Replace the current full-snapshot iCloud backup flow with entity-level CloudKit sync so a new device can restore journeys, memories, photos, passive lifelog data, daily mood, and selected settings with near-original fidelity.

**Status:** Approved design for implementation planning.

## Background

The current [ICloudSyncService](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ICloudSyncService.swift) uploads a full archive of the local user root plus a filtered `UserDefaults` snapshot, then restores by replacing the local root wholesale. That behavior is acceptable as backup, but it is not suitable as the primary sync model because:

- it is full-snapshot upload and full replacement restore
- it can overwrite newer local data
- it scales poorly with photos and large route payloads
- it does not match the product meaning of "sync"

The codebase already contains early CloudKit sync scaffolding:

- [CloudKitSyncService](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/CloudKitSyncService.swift)
- [JourneyCloudKitSync](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/JourneyCloudKitSync.swift)
- [LifelogCloudKitSync](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/LifelogCloudKitSync.swift)
- [PhotoCloudKitSync](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/PhotoCloudKitSync.swift)
- [SettingsCloudKitSync](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SettingsCloudKitSync.swift)

This design turns that scaffolding into the primary cloud sync architecture.

## Product Intent

The target user experience is:

- daily app usage syncs incrementally instead of uploading one giant backup
- a new device can restore data close to the original local state
- journeys, memories, photos, passive lifelog, and daily mood all return
- render caches are rebuilt locally rather than synced
- deletion behaves consistently across devices

This is a sync-first design, not a backup-first design.

## Current Rendering Reality

Lifelog rendering is currently composed from two independent sources:

- journey-derived render events from [JourneyStore](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/JourneyStore.swift)
- passive render events from [LifelogStore](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/LifelogStore.swift)

They are merged in [TrackRenderAdapter](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/TrackRenderAdapter.swift).

That means "restore lifelog" cannot be modeled as one monolithic blob. To achieve near-original restoration on a new device, sync must preserve:

- journeys
- passive lifelog points
- daily mood

Render snapshots, tile manifests, preview polylines, and other caches should not be synced because they are derived from source data and can be rebuilt locally.

## Chosen Architecture

Use domain-specific incremental CloudKit sync with a single orchestration layer.

### Orchestration Layer

`CloudKitSyncService` becomes the sole app-facing CloudKit entry point.

Responsibilities:

- ensure required zones exist
- schedule push and pull work
- batch work by domain
- coordinate first restore on a new device
- aggregate sync errors and status
- keep domain sync modules independent

### Sync Domains

The final sync model contains six domains:

1. `Journey`
2. `JourneyMemory`
3. `Photo`
4. `PassiveLifelogBatch`
5. `LifelogMood`
6. `Settings`

Each domain syncs raw or user-meaningful source data rather than render caches.

## CloudKit Record Schema

### Shared Fields

Every record type should include these shared fields where applicable:

- `entityID` or stable domain identifier
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

`modifiedAt` is the sync comparison timestamp.  
`clientUpdatedAt` preserves local authoring time for tie-breaking and debugging.  
`isDeleted` implements tombstones instead of immediate hard delete.

### Journey

Record type: `Journey`

Stable key:

- `journeyID`

Fields:

- `journeyID`
- `startTime`
- `endTime`
- `distance`
- `cityKey`
- `countryISO2`
- `visibility`
- `customTitle`
- `activityTag`
- `overallMemory`
- `coordinates`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

Notes:

- A journey remains the top-level route entity.
- Coordinates stay on the journey record because the render pipeline already derives journey render events from the route itself.

### JourneyMemory

Record type: `JourneyMemory`

Stable key:

- `memoryID`

Fields:

- `memoryID`
- `journeyID`
- `title`
- `notes`
- `timestamp`
- `latitude`
- `longitude`
- `locationStatus`
- `photoIDs`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

Notes:

- Memory is separated from Journey because memory changes are frequent and should not force full journey rewrites.
- `photoIDs` preserves ordering and restoration grouping.

### Photo

Record type: `Photo`

Stable key:

- `photoID`

Fields:

- `photoID`
- `memoryID`
- `journeyID`
- `sortOrder`
- `fileName`
- `assetChecksum`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`
- `asset`

Notes:

- Photos stay logically attached to a memory, but are stored separately as CloudKit assets.
- Restore reattaches them through `memoryID` and `photoIDs`.
- This keeps memory sync lightweight while still allowing near-original reconstruction.

### PassiveLifelogBatch

Record type: `PassiveLifelogBatch`

Stable key:

- `dayKey`

Fields:

- `dayKey`
- `points`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

Notes:

- Batching is by day, not by month.
- Daily batching aligns with the product's day-based lifelog experience.
- It also keeps CloudKit records smaller and easier to retry.

`points` contain the passive source data required for rendering and reconstruction, not view caches.

### LifelogMood

Record type: `LifelogMood`

Stable key:

- `dayKey`

Fields:

- `dayKey`
- `mood`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

Notes:

- Mood is part of lifelog meaning, not generic settings.
- One record per day keeps conflict handling simple and aligns with the UI.

### Settings

Record type: `Settings`

Stable key:

- one record for app-wide syncable preferences, or a small number of namespaced records if needed

Fields:

- `settingsKey`
- `data`
- `modifiedAt`
- `clientUpdatedAt`
- `schemaVersion`
- `isDeleted`
- `deviceID`

Notes:

- Only sync settings that matter across devices.
- Do not sync authentication state, guest/account migration markers, ephemeral sync status, or render caches.

## Data Ownership Rules

### Sync These

- journeys and their route coordinates
- journey memories and text/location data
- memory photos and order
- passive lifelog source points
- daily mood
- stable cross-device settings

### Do Not Sync These

- access tokens
- refresh tokens
- session blobs
- guest migration markers
- temporary cache data
- render snapshots
- tile manifests
- preview polylines
- sync status timestamps/messages
- any data that can be deterministically rebuilt from synced source data

## Restore Semantics

New device restore should be entity merge, not filesystem replacement.

Restore flow:

1. Fetch journeys
2. Fetch memories
3. Fetch photos
4. Fetch passive lifelog day batches
5. Fetch lifelog mood day records
6. Fetch syncable settings
7. Reconstruct local models and file layout
8. Rebuild derived caches locally

Expected result:

- journeys restore with memories
- memory photos reattach in the original order
- passive lifelog map data returns
- daily mood returns
- lifelog renders close to the original device after local cache rebuild

## Upload Semantics

All uploads should be incremental.

Rules:

- sync only dirty entities
- use stable record IDs
- upsert modified records
- upload photos separately from memory metadata
- allow journey and memory sync to succeed even when photo asset upload is delayed

Photo upload is allowed to lag entity metadata if needed, but reconciliation must eventually produce a complete local restore on a fresh device.

## Download Semantics

Downloads should be incremental by `modifiedAt` plus tombstone handling.

Rules:

- pull only newer remote records during normal sync
- apply tombstones before rebuilding local relationships
- reconstruct local entities by domain linkage
- rebuild render caches after merge

## Deletion Model

Deletion should be cross-device and sync-consistent.

Rules:

- deleting a journey, memory, photo, passive day batch, or mood day writes `isDeleted = true`
- new devices should honor that deletion
- hard deletion can be deferred to a cleanup phase later

Rationale:

- tombstones prevent resurrection from stale devices
- they are safer than inferring deletion from missing records

## Conflict Policy

Use a pragmatic first version:

- default policy: last-write-wins by `modifiedAt`
- tie-breaker: `clientUpdatedAt`, then `deviceID`

Domain nuances:

- `Journey`: last-write-wins is acceptable for title, visibility, and route snapshot
- `JourneyMemory`: last-write-wins is acceptable for text/location edits
- `Photo`: identity by `photoID`, order by `sortOrder`
- `PassiveLifelogBatch`: replace whole day batch if a newer record arrives
- `LifelogMood`: replace whole day value if a newer record arrives

This favors predictable recovery over sophisticated multi-writer merges for the first production-ready implementation.

## Why Daily Passive Batches

`PassiveLifelogBatch` was explicitly chosen to be daily rather than monthly because:

- lifelog UI is day-oriented
- mood is day-oriented
- debugging is easier
- CloudKit payloads stay smaller
- a bad upload only affects one day
- re-sync after conflict or corruption is more targeted

## Migration and Rollout

### Old Service Status

[ICloudSyncService](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ICloudSyncService.swift) should no longer be the primary sync path.

For the current internal test phase:

- stop using full-snapshot backup as the sync implementation
- keep old code only until the new path fully replaces call sites
- do not present the old snapshot flow as "sync"

### New Primary Path

[CloudKitSyncService](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/CloudKitSyncService.swift) becomes the primary entry point.

Expected rollout:

1. finalize schema and record mappers
2. add dirty tracking and per-domain restore logic
3. switch app lifecycle sync triggers to `CloudKitSyncService`
4. remove or disable old `ICloudSyncService` UI entry points

## Testing Strategy

### Unit Tests

- record encoding/decoding for each domain
- mapper tests between local models and CloudKit payloads
- tombstone application behavior
- restore assembly for journey-memory-photo relationships
- passive day batch merge rules
- mood day merge rules

### Integration Tests

- new-device restore from populated CloudKit data
- incremental journey update does not rewrite unrelated memories/photos
- deleting memory removes it on restored device
- passive day batch restore feeds lifelog rendering inputs
- mood survives restore and appears on the right day

### Regression Checks

- journey render events still merge with passive render events correctly
- caches rebuild after restore without corrupting source data
- settings sync excludes auth/session state

## Open Implementation Decisions

These are now intentionally narrowed:

- whether `Settings` is one record or a few namespaced records
- how to represent dirty tracking locally for each domain
- whether photo upload retry metadata lives in the photo record or local retry state

These should be resolved in the implementation plan, not by changing the approved architecture.

## Recommended Next Step

Write and execute an implementation plan that:

- introduces missing `JourneyMemory` and `LifelogMood` sync modules
- upgrades existing CloudKit sync scaffolding to the approved schema
- rewires app entry points from `ICloudSyncService` to `CloudKitSyncService`
- adds restore-first tests that prove new-device reconstruction works
