# Incremental City Cache And Cloud Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace full-journey scans in city cache rebuilding and cloud sync with incremental local indexes and a dirty sync queue.

**Architecture:** Add two persistent local metadata layers: a city membership index and a pending cloud sync queue. Interactive journey mutations update these layers incrementally, while full rebuild and full reconcile remain available only as repair tools and migration fallback.

**Tech Stack:** Swift, SwiftUI, Codable persistence, existing `JourneyStore`, `CityCache`, `JourneyCloudMigrationService`, `BackendAPIClient`

---

### Task 1: Add City Membership Index Model

**Files:**
- Create: `StreetStamps/CityMembershipIndex.swift`
- Test: `StreetStampsTests/CityMembershipIndexTests.swift`

**Step 1: Write the failing test**

Write tests covering:

- encoding/decoding index entries
- applying add/remove/update operations for one journey
- preserving stable totals for untouched cities

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps ...`
Expected: fail because the test target or model does not yet exist. If XCTest remains unavailable, document the target limitation and at least ensure compile-time references fail before implementation.

**Step 3: Write minimal implementation**

Implement:

- `CityMembershipEntry`
- `CityMembershipIndex`
- helpers to diff old/new contribution for one journey

Keep the API independent from `CityCache` first.

**Step 4: Run test to verify it passes**

Run the narrow test target if available; otherwise run a build and confirm no compile errors in the new model.

**Step 5: Commit**

```bash
git add StreetStamps/CityMembershipIndex.swift StreetStampsTests/CityMembershipIndexTests.swift
git commit -m "feat: add city membership index model"
```

### Task 2: Integrate Incremental City Updates Into CityCache

**Files:**
- Modify: `StreetStamps/CityCache.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Test: `StreetStampsTests/CityCacheIncrementalUpdateTests.swift`

**Step 1: Write the failing test**

Cover:

- completed journey add updates one city
- deleting one journey only affects its old city
- changing journey city moves counts between two cities
- changing memory count updates one city total only

**Step 2: Run test to verify it fails**

Expected: `CityCache` still requires full rebuild behavior.

**Step 3: Write minimal implementation**

Add:

- storage path for `city_membership_index.json`
- load/save logic for the index
- `applyJourneyMutation(...)` or equivalent narrow API
- migration fallback that seeds the index from a one-time rebuild if missing

Do not remove `rebuildFromJourneyStore()` yet; only stop relying on it for normal flows.

**Step 4: Run test to verify it passes**

Run the narrow tests or build verification.

**Step 5: Commit**

```bash
git add StreetStamps/CityCache.swift StreetStamps/StoragePath.swift StreetStampsTests/CityCacheIncrementalUpdateTests.swift
git commit -m "feat: update city cache incrementally"
```

### Task 3: Remove Interactive Full Rebuild Calls

**Files:**
- Modify: `StreetStamps/CityStampLibraryView.swift`
- Modify: `StreetStamps/MainView.swift`
- Modify: any other callsites of `rebuildFromJourneyStore()`
- Test: `StreetStampsTests/CityCacheCallsiteTests.swift`

**Step 1: Write the failing test**

Add a regression test or inspection-based assertion for the intended flow:

- opening city surfaces should not trigger a full rebuild
- finishing a journey should use incremental city update path

**Step 2: Run test to verify it fails**

Expected: current callsites still invoke full rebuild on appearance.

**Step 3: Write minimal implementation**

Replace normal-flow rebuild calls with:

- incremental cache application
- cached data loads
- optional deferred/background repair only when index is missing

**Step 4: Run test to verify it passes**

Run relevant verification.

**Step 5: Commit**

```bash
git add StreetStamps/CityStampLibraryView.swift StreetStamps/MainView.swift
git commit -m "refactor: stop full city rebuilds in interactive flows"
```

### Task 4: Add Pending Cloud Sync Queue Model

**Files:**
- Create: `StreetStamps/PendingCloudSyncQueue.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Test: `StreetStampsTests/PendingCloudSyncQueueTests.swift`

**Step 1: Write the failing test**

Cover:

- enqueue upsert
- enqueue delete
- collapse duplicate updates for same `journeyID`
- retry metadata persistence

**Step 2: Run test to verify it fails**

Expected: queue type does not exist yet.

**Step 3: Write minimal implementation**

Implement:

- queue entry model
- load/save helpers
- enqueue/ack/fail operations
- compaction by `journeyID`

**Step 4: Run test to verify it passes**

Run narrow verification.

**Step 5: Commit**

```bash
git add StreetStamps/PendingCloudSyncQueue.swift StreetStamps/StoragePath.swift StreetStampsTests/PendingCloudSyncQueueTests.swift
git commit -m "feat: add pending cloud sync queue"
```

### Task 5: Emit Queue Events From Journey Mutations

**Files:**
- Modify: `StreetStamps/MainView.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Modify: any journey delete/edit visibility paths
- Test: `StreetStampsTests/JourneyCloudQueueEmitterTests.swift`

**Step 1: Write the failing test**

Cover:

- completed public/friends-only journey enqueues `upsert`
- `private` journey does not enqueue upload
- visibility `shareable -> private` enqueues `delete`
- deleting shareable journey enqueues `delete`

**Step 2: Run test to verify it fails**

Expected: save flows still call `migrateAll()` directly.

**Step 3: Write minimal implementation**

Replace direct full-sync triggers with queue enqueue operations.

**Step 4: Run test to verify it passes**

Run relevant verification.

**Step 5: Commit**

```bash
git add StreetStamps/MainView.swift StreetStamps/MyJourneysView.swift StreetStamps/JourneyStore.swift
git commit -m "feat: enqueue cloud sync from journey mutations"
```

### Task 6: Add Background Queue Flush Worker

**Files:**
- Modify: `StreetStamps/JourneyCloudMigrationService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/BackendAPIClient.swift` if a narrow delete/upsert API is needed
- Test: `StreetStampsTests/JourneyCloudSyncWorkerTests.swift`

**Step 1: Write the failing test**

Cover:

- flush uploads queued `upsert` journeys only
- flush removes successful items
- flush leaves failed items with retry metadata
- no token means no-op

**Step 2: Run test to verify it fails**

Expected: service only supports full migrate and full download merge.

**Step 3: Write minimal implementation**

Add:

- queue-backed flush API
- batch processing
- retry/backoff metadata updates
- triggers on launch, auth available, foreground

Keep `migrateAll()` temporarily for repair/manual use.

**Step 4: Run test to verify it passes**

Run relevant verification.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyCloudMigrationService.swift StreetStamps/StreetStampsApp.swift StreetStamps/BackendAPIClient.swift
git commit -m "feat: flush cloud sync queue in background"
```

### Task 7: Relegate Full Rebuild And Full Migrate To Repair Paths

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/JourneyCloudMigrationService.swift`
- Modify: debug/repair surfaces as needed
- Test: `StreetStampsTests/RepairFlowTests.swift`

**Step 1: Write the failing test**

Cover:

- manual repair still triggers full city rebuild
- manual repair still supports full cloud reconcile
- normal save path no longer invokes full migrate

**Step 2: Run test to verify it fails**

Expected: current flows still couple repair and normal behavior.

**Step 3: Write minimal implementation**

Move full rebuild/reconcile behind explicit repair actions and background fallback only.

**Step 4: Run test to verify it passes**

Run relevant verification.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsView.swift StreetStamps/JourneyCloudMigrationService.swift
git commit -m "refactor: reserve full rebuild and reconcile for repair paths"
```

### Task 8: Verification And Cleanup

**Files:**
- Modify: any touched files from previous tasks
- Optional docs update: `docs/plans/2026-03-08-incremental-city-cache-cloud-sync-design.md`

**Step 1: Run focused verification**

Run the narrowest available verification for touched areas. If XCTest remains unavailable in the scheme, record that clearly and run build verification instead.

Suggested commands:

```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedDataIncrementalSync
```

**Step 2: Manual behavior checklist**

Verify:

- finish one public journey only enqueues/syncs one item
- open collection/cities does not trigger full rebuild
- visibility change updates queue correctly
- app relaunch preserves queue and index files

**Step 3: Final cleanup**

Remove dead full-scan callsites, keep only explicit repair entrypoints, and tighten comments/docstrings.

**Step 4: Commit**

```bash
git add StreetStamps docs/plans/2026-03-08-incremental-city-cache-cloud-sync-design.md docs/plans/2026-03-08-incremental-city-cache-cloud-sync-implementation.md
git commit -m "docs: plan incremental city cache and cloud sync"
```
