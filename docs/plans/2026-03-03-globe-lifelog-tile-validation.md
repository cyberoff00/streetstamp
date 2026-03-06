# Globe/Lifelog Tile Index Validation (2026-03-04)

## Acceptance Checklist

- [x] Migration behavior
  - `TrackTileStore` persists `manifest.json` and per-tile files.
  - Restart path validated by `test_store_loadsManifestAndTilesAfterRestart`.
- [x] Warm-open responsiveness
  - Added lightweight `refreshData` timing log in `MapboxGlobeView`: `⏱️ globe refreshData <ms>`.
- [x] Visual parity safety rails
  - Globe continues using existing Mapbox style/layers; only route data source switched via `TrackRenderAdapter`.
  - Lifelog map keeps fallback (`mapPolylineViewport`) when tile query yields no data.
- [x] User-switch isolation
  - `TrackTileStore.rebind(paths:)` wired on user switch in `StreetStampsApp`.

## Automated Verification

### Tests

- Command:
  - `xcodebuild test -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -derivedDataPath /Users/liuyang/Downloads/StreetStamps_fixed_v3_3/build/DerivedDataMain -only-testing:StreetStampsTests/TrackTileBuilderTests -only-testing:StreetStampsTests/TrackTileStoreTests -only-testing:StreetStampsTests/TrackRenderAdapterTests`
- Result: PASS
  - `TrackTileBuilderTests` (3 passed)
  - `TrackTileStoreTests` (3 passed)
  - `TrackRenderAdapterTests` (2 passed)

### Builds

- `xcodebuild build -scheme StreetStamps ... -derivedDataPath /Users/liuyang/Downloads/StreetStamps_fixed_v3_3/build/DerivedDataMain`
  - Result: `BUILD SUCCEEDED`
- `xcodebuild build -quiet -scheme TrackingWidgeExtension ... -derivedDataPath /Users/liuyang/Downloads/StreetStamps_fixed_v3_3/build/DerivedDataWidget`
  - Result: success (exit code 0)
- `xcodebuild build -quiet -scheme StreetStampsWatch ... -derivedDataPath /Users/liuyang/Downloads/StreetStamps_fixed_v3_3/build/DerivedDataWatch`
  - Initial result: missing cached Mapbox XCFramework artifacts in `DerivedDataWatch`.
  - Action: synced Mapbox artifacts from `DerivedDataMain` cache and reran.
  - Final result: success (exit code 0)

## Notes

- This validation run focused on code-level and build-level verification.
- Manual simulator smoke (country far-view, city highlight, near-route parity) is still recommended before merge.
