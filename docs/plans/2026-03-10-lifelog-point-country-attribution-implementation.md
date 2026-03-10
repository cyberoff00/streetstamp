# Lifelog Point Country Attribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add point-level passive country attribution sidecar indexes so new lifelog passive data can render China and non-China runs correctly without adding foreground tracking latency.

**Architecture:** Extend passive point persistence with a cheap spatial cell key, add background country-resolution sidecar indexes (`cell -> iso2`, `point -> iso2`, and compressed country runs), and update lifelog/globe render paths to consume country-aware runs instead of a single request-level country. Keep raw WGS84 points immutable and treat unresolved points as WGS84 until confirmed.

**Tech Stack:** Swift, SwiftUI, Combine, CoreLocation, MapKit, XCTest

---

### Task 1: Document the current passive rendering limitation with tests

**Files:**
- Modify: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Modify: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Write the failing tests**

Add tests that construct passive-only segments spanning two countries and assert that the render builder can represent China and non-China portions independently instead of applying a single `countryISO2` to the entire result.

**Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests
```

Expected: FAIL because passive render flows still consume one request-level country value.

**Step 3: Write minimal implementation**

Add the smallest test helpers needed to express country-aware passive runs in fixtures without changing production behavior yet.

**Step 4: Run tests to verify the test harness compiles**

Run the same `xcodebuild test` command.
Expected: FAIL at the intended assertions instead of fixture/setup errors.

**Step 5: Commit**

```bash
git add StreetStampsTests/LifelogRenderSnapshotTests.swift StreetStampsTests/GlobeRefreshCoordinatorTests.swift
git commit -m "test: document passive country attribution gaps"
```

### Task 2: Add raw-point `cellID` support for new passive data

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/TrackTileModels.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing test**

Add a store test that appends a new passive point and asserts the persisted in-memory representation includes a deterministic `cellID` while preserving the existing raw WGS84 coordinate fields.

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogStoreBehaviorTests
```

Expected: FAIL because passive point records do not yet carry a spatial cell key.

**Step 3: Write minimal implementation**

Extend the passive point model for newly written records:

```swift
private struct LifelogTrackPoint: Codable {
    var id: String
    var lat: Double
    var lon: Double
    var timestamp: Date
    var accuracy: Double?
    var cellID: String
}
```

Add a local helper in `LifelogStore` to compute `cellID` in O(1) time and populate it for new points. Preserve backward decoding for legacy payloads that do not yet contain these fields.

**Step 4: Run test to verify it passes**

Run the same focused test command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogStore.swift StreetStamps/TrackTileModels.swift StreetStampsTests/LifelogStoreBehaviorTests.swift
git commit -m "feat: store passive point cell ids for new data"
```

### Task 3: Add rebuildable passive country sidecar models and storage

**Files:**
- Create: `StreetStamps/LifelogCountryAttributionStore.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing test**

Add tests covering save/load of:
- cell country cache entries
- point country index entries
- compressed country run entries

using an isolated temporary storage path.

**Step 2: Run test to verify it fails**

Run the focused attribution store tests.
Expected: FAIL because no sidecar persistence layer exists.

**Step 3: Write minimal implementation**

Create a dedicated sidecar store with versioned Codable payloads:

```swift
struct LifelogCellCountryRecord: Codable, Equatable
struct LifelogPointCountryRecord: Codable, Equatable
struct LifelogCountryRunRecord: Codable, Equatable

final class LifelogCountryAttributionStore {
    func load() throws -> LifelogCountryAttributionSnapshot
    func save(_ snapshot: LifelogCountryAttributionSnapshot) throws
}
```

Add `StoragePath` URLs for the new sidecar files. Keep the raw passive route file unchanged.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogCountryAttributionStore.swift StreetStamps/StoragePath.swift StreetStampsTests/LifelogStoreBehaviorTests.swift
git commit -m "feat: add passive country attribution sidecar storage"
```

### Task 4: Build the background cell-country resolution pipeline

**Files:**
- Create: `StreetStamps/LifelogCountryAttributionCoordinator.swift`
- Modify: `StreetStamps/ReverseGeocodeService.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing test**

Add tests that feed new passive points with repeated `cellID`s and assert:
- unresolved cells are deduplicated
- authoritative reverse geocode results are cached per cell
- unresolved points remain `unknown` when resolution is unavailable

**Step 2: Run test to verify it fails**

Run the focused attribution tests.
Expected: FAIL because there is no background cell-resolution coordinator.

**Step 3: Write minimal implementation**

Create a coordinator that:

- accepts appended passive points
- identifies unresolved cells
- resolves each cell through the canonical reverse-geocode path
- persists `cellID -> iso2`
- does not block the foreground append path

Expose a small interface from `LifelogStore` to enqueue attribution work after point acceptance.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogCountryAttributionCoordinator.swift StreetStamps/ReverseGeocodeService.swift StreetStamps/LifelogStore.swift StreetStampsTests/LifelogStoreBehaviorTests.swift
git commit -m "feat: resolve passive country attribution by cell in background"
```

### Task 5: Build point-country and country-run indexes incrementally

**Files:**
- Modify: `StreetStamps/LifelogCountryAttributionCoordinator.swift`
- Create: `StreetStamps/LifelogCountryRunBuilder.swift`
- Test: `StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift`

**Step 1: Write the failing test**

Add tests proving that:
- points inherit `iso2` from their resolved cell
- adjacent points with the same `iso2` collapse into one run
- `unknown` breaks runs
- incremental updates only rebuild the tail region

**Step 2: Run test to verify it fails**

Run the focused country-run tests.
Expected: FAIL because point-level attribution is not yet compressed into renderable runs.

**Step 3: Write minimal implementation**

Introduce a run builder such as:

```swift
struct LifelogCountryRun {
    let startPointID: String
    let endPointID: String
    let iso2: String?
}
```

Build point-country mappings from cell cache entries, then compress them into country runs. Add an incremental rebuild API that recalculates only the trailing window affected by newly resolved cells.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogCountryAttributionCoordinator.swift StreetStamps/LifelogCountryRunBuilder.swift StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift
git commit -m "feat: derive incremental passive country runs"
```

### Task 6: Stop bbox-only signals from driving GCJ

**Files:**
- Modify: `StreetStamps/LocationHub.swift`
- Modify: `StreetStamps/ChinaCoordinateTransform.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`

**Step 1: Write the failing test**

Add tests asserting that an unresolved passive run does not receive GCJ conversion even if a coarse China bbox hint is present, while a confirmed `resolvedISO2 == "CN"` run does.

**Step 2: Run test to verify it fails**

Run the focused render snapshot tests.
Expected: FAIL because current flows can still rely on request-level country state rather than confirmed run attribution.

**Step 3: Write minimal implementation**

Separate provisional scheduling hints from confirmed render attribution:
- keep bbox logic only as an internal scheduling hint if still needed
- prevent provisional country values from directly enabling GCJ in passive rendering

Leave `ChinaCoordinateTransform` product gating based only on authoritative ISO2 or canonical city keys.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LocationHub.swift StreetStamps/ChinaCoordinateTransform.swift StreetStampsTests/LifelogRenderSnapshotTests.swift
git commit -m "fix: require confirmed passive country attribution for gcj"
```

### Task 7: Update lifelog render snapshot building to consume country-aware runs

**Files:**
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/RouteRendering.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Test: `StreetStampsTests/LifelogFootprintRenderPlannerTests.swift`

**Step 1: Write the failing tests**

Add tests asserting that lifelog snapshot building:
- splits one passive path into multiple country-aware runs
- converts only the confirmed China runs
- leaves `unknown` and non-China runs in WGS84

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/LifelogFootprintRenderPlannerTests
```

Expected: FAIL because snapshot building still accepts one `countryISO2` per request.

**Step 3: Write minimal implementation**

Replace request-level passive country adaptation with country-aware runs derived from the sidecar indexes. Pass run-local country information into far-route and footprint builders so each run is adapted independently.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogRenderSnapshot.swift StreetStamps/LifelogView.swift StreetStamps/RouteRendering.swift StreetStampsTests/LifelogRenderSnapshotTests.swift StreetStampsTests/LifelogFootprintRenderPlannerTests.swift
git commit -m "feat: render passive lifelog paths by attributed country runs"
```

### Task 8: Update globe passive rendering to consume country-aware runs

**Files:**
- Modify: `StreetStamps/TrackRenderAdapter.swift`
- Modify: `StreetStamps/GlobeRefreshCoordinator.swift`
- Modify: `StreetStamps/MapboxGlobeView.swift`
- Test: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Write the failing test**

Add globe tests asserting that passive-only globe routes can emit both China and non-China runs from the same underlying passive data set.

**Step 2: Run test to verify it fails**

Run the focused globe tests.
Expected: FAIL because globe passive routes still inherit one `countryISO2`.

**Step 3: Write minimal implementation**

Change the globe passive route adapter to emit country-aware route groups or route fragments derived from the passive country-run index. Preserve existing route styling and flight behavior while allowing per-run GCJ adaptation.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/TrackRenderAdapter.swift StreetStamps/GlobeRefreshCoordinator.swift StreetStamps/MapboxGlobeView.swift StreetStampsTests/GlobeRefreshCoordinatorTests.swift
git commit -m "feat: render globe passive routes by attributed country runs"
```

### Task 9: Wire invalidation and warmup around attribution updates

**Files:**
- Modify: `StreetStamps/LifelogRenderCacheCoordinator.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift`

**Step 1: Write the failing test**

Add tests ensuring that when passive country attribution changes:
- today’s render cache is invalidated
- warmup requests use the updated attribution snapshot
- unrelated historical days are not eagerly rebuilt

**Step 2: Run test to verify it fails**

Run the focused render cache coordinator tests.
Expected: FAIL because attribution changes do not yet participate in cache invalidation.

**Step 3: Write minimal implementation**

Emit attribution-change notifications from the sidecar coordinator, hook them into `LifelogRenderCacheCoordinator`, and invalidate affected day/view snapshots. Keep the rebuild scope minimal.

**Step 4: Run test to verify it passes**

Run the same focused tests.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogRenderCacheCoordinator.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift
git commit -m "refactor: refresh lifelog caches on country attribution updates"
```

### Task 10: Verify performance-sensitive and regression coverage

**Files:**
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Test: `StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift`
- Test: `StreetStampsTests/LifelogFootprintRenderPlannerTests.swift`
- Test: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Run focused verification**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -only-testing:StreetStampsTests/LifelogStoreBehaviorTests \
  -only-testing:StreetStampsTests/LifelogRenderSnapshotTests \
  -only-testing:StreetStampsTests/LifelogRenderCacheCoordinatorTests \
  -only-testing:StreetStampsTests/LifelogFootprintRenderPlannerTests \
  -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests
```

Expected: PASS.

**Step 2: Run broader passive/lifelog regression coverage if time permits**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests
```

Expected: PASS or a short list of unrelated existing failures.

**Step 3: Commit**

```bash
git add StreetStampsTests/LifelogStoreBehaviorTests.swift StreetStampsTests/LifelogRenderSnapshotTests.swift StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift StreetStampsTests/LifelogFootprintRenderPlannerTests.swift StreetStampsTests/GlobeRefreshCoordinatorTests.swift
git commit -m "test: verify passive country attribution rendering flow"
```
