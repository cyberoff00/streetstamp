# Globe/Lifelog Tile Index Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split authoritative data into Journey + Passive Lifelog, then render Globe/Lifelog through a persisted tile index so first-open is smooth without changing current visual style.

**Architecture:** Keep `JourneyStore` and passive lifelog as separate source-of-truth stores. Add a new `TrackTileStore` as rendering index layer with per-user disk persistence and revision-based incremental rebuild. Update Globe/Lifelog read paths to consume tiles instead of full-history segmentation.

**Tech Stack:** SwiftUI, CoreLocation, MapboxMaps, JSON persistence in Application Support/Caches, xcodebuild.

---

### Task 1: Add test target and tile builder test harness

**Files:**
- Modify: `StreetStamps.xcodeproj/project.pbxproj`
- Create: `StreetStampsTests/TrackTileBuilderTests.swift`

**Step 1: Write the failing test**

```swift
func test_buildTiles_splitsByTileAndPreservesSourceType() {
    let events = [
        TrackRenderEvent(... journey ...),
        TrackRenderEvent(... passive ...)
    ]
    let out = TrackTileBuilder.build(events: events, zoom: 10)
    XCTAssertFalse(out.tiles.isEmpty)
    XCTAssertTrue(out.tiles.values.flatMap(\ .segments).contains { $0.sourceType == .journey })
    XCTAssertTrue(out.tiles.values.flatMap(\ .segments).contains { $0.sourceType == .passive })
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: FAIL because `TrackTileBuilder` and tile models do not exist yet.

**Step 3: Write minimal implementation scaffolding**

Add empty model/type stubs so tests compile but still fail logically.

**Step 4: Run test to verify expected failure mode**

Run same command; expected: compile passes for stubs, assertion fails.

**Step 5: Commit**

```bash
git add StreetStamps.xcodeproj/project.pbxproj StreetStampsTests/TrackTileBuilderTests.swift
git commit -m "test: add tile builder test harness"
```

### Task 2: Split passive lifelog storage and one-time migration

**Files:**
- Modify: `StreetStamps/StoragePath.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Create: `StreetStamps/LifelogMigrationService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`

**Step 1: Write the failing test**

```swift
func test_migrateLegacyLifelog_renamesOldFileToBak_andCreatesEmptyPassiveFile() throws
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test ...`
Expected: FAIL because migration service does not exist.

**Step 3: Implement minimal migration**

- Add `lifelogPassiveRouteURL` to `StoragePath`.
- Add migration marker path.
- Implement rename `lifelog_route.json -> lifelog_route.json.bak` (best-effort).
- Initialize empty passive file.
- Invoke migration during app bootstrap before store loads.

**Step 4: Run test to verify pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/StoragePath.swift StreetStamps/LifelogStore.swift StreetStamps/LifelogMigrationService.swift StreetStamps/StreetStampsApp.swift
git commit -m "feat: split passive lifelog storage and migrate legacy file to bak"
```

### Task 3: Stop journey backfill into passive source

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/GlobeViewScreen.swift`

**Step 1: Write the failing test**

```swift
func test_lifelogStore_doesNotArchiveJourneyIntoPassivePoints() {
    // after archive call, passive point count should remain unchanged
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test ...`
Expected: FAIL because archive path still appends journey coordinates.

**Step 3: Implement minimal change**

- Remove journey-coordinate backfill side effects from passive storage path.
- Keep any APIs required by callers as no-op/deprecated wrappers for compatibility.
- Remove Globe first-open backfill kickoff.

**Step 4: Run test to verify pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogStore.swift StreetStamps/GlobeViewScreen.swift
git commit -m "refactor: decouple passive lifelog from journey backfill"
```

### Task 4: Implement tile domain models and builder

**Files:**
- Create: `StreetStamps/TrackTileModels.swift`
- Create: `StreetStamps/TrackTileBuilder.swift`
- Modify: `StreetStampsTests/TrackTileBuilderTests.swift`

**Step 1: Write failing tests for simplification and tiling**

```swift
func test_builder_generatesLowerPointDensityForLowZoom()
func test_builder_producesDeterministicTileKeying()
```

**Step 2: Run tests and confirm fail**

Run: `xcodebuild test ...`
Expected: FAIL.

**Step 3: Implement minimal builder**

- Tile key mapping `z/x/y`.
- Segment simplification by zoom tier.
- Preserve `sourceType` (`journey`/`passive`).

**Step 4: Run tests and confirm pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/TrackTileModels.swift StreetStamps/TrackTileBuilder.swift StreetStampsTests/TrackTileBuilderTests.swift
git commit -m "feat: add track tile models and builder"
```

### Task 5: Implement TrackTileStore persistence and revision invalidation

**Files:**
- Create: `StreetStamps/TrackTileStore.swift`
- Create: `StreetStamps/TrackTileManifest.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Create: `StreetStampsTests/TrackTileStoreTests.swift`

**Step 1: Write failing tests**

```swift
func test_store_loadsManifestAndTilesAfterRestart()
func test_revisionMismatch_triggersIncrementalRebuild()
```

**Step 2: Run tests and confirm fail**

Run: `xcodebuild test ...`
Expected: FAIL.

**Step 3: Implement minimal store**

- Read/write `manifest.json`.
- Read/write per-tile files.
- Compare `journeyRevision + passiveRevision` for invalidation.
- Expose API: `tiles(for viewport:..., zoom:...)`.

**Step 4: Run tests and confirm pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/TrackTileStore.swift StreetStamps/TrackTileManifest.swift StreetStamps/StoragePath.swift StreetStampsTests/TrackTileStoreTests.swift
git commit -m "feat: add persistent track tile store with revision invalidation"
```

### Task 6: Wire TrackTileStore startup and incremental updates

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/JourneyStore.swift`
- Modify: `StreetStamps/LifelogStore.swift`

**Step 1: Write failing integration test**

```swift
func test_newPassivePoint_updatesOnlyAffectedTiles()
```

**Step 2: Run tests and confirm fail**

Run: `xcodebuild test ...`
Expected: FAIL.

**Step 3: Implement minimal wiring**

- Create `TrackTileStore` app singleton/state object.
- Emit revision/update events from JourneyStore and LifelogStore.
- Trigger async incremental rebuild on event.

**Step 4: Run tests and confirm pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/JourneyStore.swift StreetStamps/LifelogStore.swift
git commit -m "feat: wire tile store updates from journey and passive sources"
```

### Task 7: Switch Globe read path to tile index (style unchanged)

**Files:**
- Modify: `StreetStamps/GlobeViewScreen.swift`
- Modify: `StreetStamps/MapboxGlobeView.swift`
- Create: `StreetStamps/TrackRenderAdapter.swift`

**Step 1: Write failing UI-level assertion test/smoke**

```swift
func test_globeUsesTrackRenderAdapter_notFullLifelogSegmentation()
```

**Step 2: Run tests/smoke and confirm fail**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: existing path still references full `globeJourneys`.

**Step 3: Implement minimal adapter swap**

- Build journeys/features from visible tiles through adapter.
- Keep current country/city/route style parameters untouched.
- Remove repeated full-history computations in `body` path.

**Step 4: Verify build + manual smoke**

Run build command above.
Expected: BUILD SUCCEEDED; Globe still shows country far-view, city highlight, near routes.

**Step 5: Commit**

```bash
git add StreetStamps/GlobeViewScreen.swift StreetStamps/MapboxGlobeView.swift StreetStamps/TrackRenderAdapter.swift
git commit -m "refactor: render globe routes from tile index"
```

### Task 8: Switch Lifelog map read path to tile index

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/MapView.swift` (if shared polyline helpers are used)

**Step 1: Write failing test**

```swift
func test_lifelogMapReadsTilesForViewportAndZoom()
```

**Step 2: Run tests and confirm fail**

Run: `xcodebuild test ...`
Expected: FAIL (still reading full sampled coordinates path).

**Step 3: Implement minimal change**

- Query tile store by viewport and LOD.
- Keep fallback path for empty-tile bootstrap only.

**Step 4: Run tests/build and confirm pass**

Run: `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogView.swift StreetStamps/LifelogStore.swift StreetStamps/MapView.swift
git commit -m "refactor: render lifelog map from tile index"
```

### Task 9: Verification, instrumentation, and docs

**Files:**
- Modify: `StreetStamps/MapboxGlobeView.swift` (lightweight timing logs)
- Create: `docs/plans/2026-03-03-globe-lifelog-tile-validation.md`

**Step 1: Add failing acceptance checklist**

Document checks for:
- migration behavior,
- warm-open responsiveness,
- visual parity,
- user-switch isolation.

**Step 2: Run verification commands**

Run:
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
- `xcodebuild build -quiet -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -derivedDataPath build/DerivedDataWidget`
- `xcodebuild build -quiet -scheme StreetStampsWatch -project StreetStamps.xcodeproj -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (42mm),OS=11.2' -derivedDataPath build/DerivedDataWatch`

Expected: BUILD SUCCEEDED.

**Step 3: Complete validation report**

Record measured open timing and parity notes.

**Step 4: Commit**

```bash
git add StreetStamps/MapboxGlobeView.swift docs/plans/2026-03-03-globe-lifelog-tile-validation.md
git commit -m "docs: validate tile-index rendering migration"
```

