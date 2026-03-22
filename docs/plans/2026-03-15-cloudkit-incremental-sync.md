# CloudKit Incremental Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace full-snapshot iCloud sync with entity-level CloudKit sync that restores journeys, memories, photos, passive lifelog day batches, daily mood, and selected settings on a new device.

**Architecture:** Use `CloudKitSyncService` as the sole orchestration layer and implement six domain sync modules: Journey, JourneyMemory, Photo, PassiveLifelogBatch, LifelogMood, and Settings. Sync source data incrementally with tombstones and rebuild derived caches locally after restore.

**Tech Stack:** Swift, Swift Concurrency, CloudKit, XCTest

---

### Task 1: Align CloudKit schema constants with the approved domain model

**Files:**
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Modify: `StreetStamps/JourneyCloudKitSync.swift`
- Modify: `StreetStamps/LifelogCloudKitSync.swift`
- Modify: `StreetStamps/PhotoCloudKitSync.swift`
- Modify: `StreetStamps/SettingsCloudKitSync.swift`
- Test: `StreetStampsTests/CloudKitSchemaTests.swift`

**Step 1: Write the failing test**

Add tests that assert the record type constants include:

- `Journey`
- `JourneyMemory`
- `Photo`
- `PassiveLifelogBatch`
- `LifelogMood`
- `Settings`

and that old snapshot-oriented names are not used for the new sync path.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CloudKitSchemaTests`

Expected: FAIL because the current constants and services do not fully match the approved schema.

**Step 3: Write minimal implementation**

Update CloudKit record type constants and shared field naming so all sync modules use the same domain vocabulary.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm the schema test passes.

**Step 5: Commit**

```bash
git add StreetStamps/CloudKitSyncService.swift StreetStamps/JourneyCloudKitSync.swift StreetStamps/LifelogCloudKitSync.swift StreetStamps/PhotoCloudKitSync.swift StreetStamps/SettingsCloudKitSync.swift StreetStampsTests/CloudKitSchemaTests.swift
git commit -m "refactor: align cloudkit schema with incremental sync design"
```

### Task 2: Add local sync metadata models and mapping helpers

**Files:**
- Modify: `StreetStamps/JourneyStore.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Create: `StreetStamps/CloudKitSyncModels.swift`
- Create: `StreetStamps/CloudKitSyncMappers.swift`
- Test: `StreetStampsTests/CloudKitSyncMapperTests.swift`

**Step 1: Write the failing test**

Add tests that build local Journey, Memory, Photo, passive day, and mood inputs and assert they map to stable CloudKit payload models with:

- stable IDs
- `modifiedAt`
- `clientUpdatedAt`
- `isDeleted`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CloudKitSyncMapperTests`

Expected: FAIL because mapper models do not exist yet.

**Step 3: Write minimal implementation**

Create shared sync DTOs and conversion helpers from local models to CloudKit records and back.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm the mapper tests pass.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyStore.swift StreetStamps/LifelogStore.swift StreetStamps/CloudKitSyncModels.swift StreetStamps/CloudKitSyncMappers.swift StreetStampsTests/CloudKitSyncMapperTests.swift
git commit -m "feat: add cloudkit sync models and mappers"
```

### Task 3: Implement JourneyMemory sync as a first-class domain

**Files:**
- Create: `StreetStamps/JourneyMemoryCloudKitSync.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Test: `StreetStampsTests/JourneyMemoryCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- a memory is uploaded as its own record
- `journeyID` linkage is preserved
- a deleted memory becomes a tombstone

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyMemoryCloudKitSyncTests`

Expected: FAIL because the memory sync module is missing.

**Step 3: Write minimal implementation**

Implement `JourneyMemoryCloudKitSync` with zone setup, upsert, fetch-by-modifiedAt, and tombstone support.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild` command and confirm tests pass.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyMemoryCloudKitSync.swift StreetStamps/CloudKitSyncService.swift StreetStampsTests/JourneyMemoryCloudKitSyncTests.swift
git commit -m "feat: add journey memory cloudkit sync"
```

### Task 4: Upgrade Journey sync to support restore-safe incremental behavior

**Files:**
- Modify: `StreetStamps/JourneyCloudKitSync.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Test: `StreetStampsTests/JourneyCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- stable record IDs per journey
- incremental fetch by `modifiedAt`
- tombstone behavior
- route coordinates survive round-trip restore

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `JourneyCloudKitSyncTests`.

Expected: FAIL because current journey sync is scaffold-level only.

**Step 3: Write minimal implementation**

Update journey record serialization and fetch logic to use the approved schema and restore-safe merge semantics.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyCloudKitSync.swift StreetStamps/CloudKitSyncService.swift StreetStampsTests/JourneyCloudKitSyncTests.swift
git commit -m "feat: upgrade journey cloudkit sync"
```

### Task 5: Upgrade Photo sync for ordered restore and asset retries

**Files:**
- Modify: `StreetStamps/PhotoCloudKitSync.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Test: `StreetStampsTests/PhotoCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- photo records keep `memoryID`, `journeyID`, and `sortOrder`
- asset checksum is stored
- tombstoned photos are excluded on restore

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `PhotoCloudKitSyncTests`.

Expected: FAIL because current photo sync does not fully model ordered restore metadata.

**Step 3: Write minimal implementation**

Update photo sync to store ordered linkage metadata, asset checksum, and retry-safe upload behavior.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/PhotoCloudKitSync.swift StreetStamps/CloudKitSyncService.swift StreetStampsTests/PhotoCloudKitSyncTests.swift
git commit -m "feat: upgrade photo cloudkit sync"
```

### Task 6: Convert passive lifelog sync from coarse scaffold to daily batch sync

**Files:**
- Modify: `StreetStamps/LifelogCloudKitSync.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Test: `StreetStampsTests/LifelogCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- passive points upload by `dayKey`
- only the modified day batch is rewritten
- restore reconstructs passive points for the right day

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `LifelogCloudKitSyncTests`.

Expected: FAIL because current lifelog sync is too thin and not aligned to the approved daily schema.

**Step 3: Write minimal implementation**

Refactor `LifelogCloudKitSync` to store one passive batch per day and add mapping helpers from `LifelogStore` source data.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogCloudKitSync.swift StreetStamps/LifelogStore.swift StreetStampsTests/LifelogCloudKitSyncTests.swift
git commit -m "feat: add daily passive lifelog cloudkit sync"
```

### Task 7: Add daily mood sync as a dedicated lifelog domain

**Files:**
- Create: `StreetStamps/LifelogMoodCloudKitSync.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Test: `StreetStampsTests/LifelogMoodCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- one mood record per day
- clearing mood writes a tombstone
- restored mood reappears on the same day

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `LifelogMoodCloudKitSyncTests`.

Expected: FAIL because the mood sync module is missing.

**Step 3: Write minimal implementation**

Implement `LifelogMoodCloudKitSync` and the necessary `LifelogStore` extraction and restore helpers.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogMoodCloudKitSync.swift StreetStamps/LifelogStore.swift StreetStamps/CloudKitSyncService.swift StreetStampsTests/LifelogMoodCloudKitSyncTests.swift
git commit -m "feat: add lifelog mood cloudkit sync"
```

### Task 8: Narrow settings sync to a safe whitelist

**Files:**
- Modify: `StreetStamps/SettingsCloudKitSync.swift`
- Modify: `StreetStamps/AppSettings.swift`
- Test: `StreetStampsTests/SettingsCloudKitSyncTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- only approved settings keys are synced
- auth/session state is excluded
- sync status metadata is excluded

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `SettingsCloudKitSyncTests`.

Expected: FAIL because the whitelist is not enforced yet.

**Step 3: Write minimal implementation**

Implement a strict allowlist for cross-device settings.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsCloudKitSync.swift StreetStamps/AppSettings.swift StreetStampsTests/SettingsCloudKitSyncTests.swift
git commit -m "feat: whitelist syncable settings"
```

### Task 9: Implement restore assembly for new-device reconstruction

**Files:**
- Modify: `StreetStamps/CloudKitSyncService.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Test: `StreetStampsTests/CloudKitRestoreAssemblyTests.swift`

**Step 1: Write the failing test**

Add an end-to-end restore assembly test that verifies:

- journeys restore
- memories reattach to journeys
- photos reattach in order
- passive day batches restore
- mood restores by day
- local derived caches are rebuilt instead of synced

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `CloudKitRestoreAssemblyTests`.

Expected: FAIL because restore assembly does not exist yet.

**Step 3: Write minimal implementation**

Implement the restore pipeline in `CloudKitSyncService` and local model stores.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/CloudKitSyncService.swift StreetStamps/JourneyStore.swift StreetStamps/LifelogStore.swift StreetStamps/StoragePath.swift StreetStampsTests/CloudKitRestoreAssemblyTests.swift
git commit -m "feat: assemble cloudkit restore into local stores"
```

### Task 10: Rewire app entry points from full snapshot sync to the new service

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/ICloudSyncService.swift`
- Test: `StreetStampsTests/CloudKitSyncEntryPointTests.swift`

**Step 1: Write the failing test**

Add tests that verify:

- app startup uses `CloudKitSyncService` for restore/sync
- settings actions no longer use full filesystem replacement as sync
- the old snapshot service is disabled or demoted from the main path

**Step 2: Run test to verify it fails**

Run the focused `xcodebuild test` command for `CloudKitSyncEntryPointTests`.

Expected: FAIL because current entry points still reference `ICloudSyncService`.

**Step 3: Write minimal implementation**

Rewire startup and settings flow to use the new sync orchestration service. Demote or disable old snapshot code for internal testing.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm PASS.

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/SettingsView.swift StreetStamps/ICloudSyncService.swift StreetStampsTests/CloudKitSyncEntryPointTests.swift
git commit -m "refactor: switch app sync entry points to cloudkit incremental service"
```

### Task 11: Run end-to-end verification

**Files:**
- Test: `StreetStampsTests`

**Step 1: Run focused domain tests**

Run each focused `xcodebuild test` command from the tasks above until all pass.

**Step 2: Run broader verification**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: PASS for the test suite or a clearly documented list of unrelated existing failures.

**Step 3: Sanity-check app behavior**

Verify manually or with existing test hooks:

- create/update/delete journey
- edit memory text
- add/remove/reorder photo
- passive lifelog day persists
- mood persists and restores
- new-device restore path rebuilds caches

**Step 4: Commit final integration**

```bash
git add .
git commit -m "feat: replace snapshot icloud sync with incremental cloudkit sync"
```
