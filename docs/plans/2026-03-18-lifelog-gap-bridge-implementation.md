# Lifelog Gap Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Render adjacent `Lifelog` gap breaks as flight-like dashed bridges without modifying stored track truth.

**Architecture:** Keep automatic gap detection exactly as it is today, but add render-only bridge segments after `Lifelog` day runs are built. The bridge uses only the previous run end and next run start, and it reuses the existing dashed route styling path so the appearance matches solid segments except for the dash pattern.

**Tech Stack:** Swift, SwiftUI, CoreLocation, MapKit, XCTest

---

### Task 1: Lock adjacent-gap bridge behavior in tests

**Files:**
- Modify: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write a failing snapshot test for one adjacent passive gap**

Add a test that builds two passive runs for one day with a forced break and asserts the day snapshot includes:
- the original solid render groups
- exactly one additional dashed bridge between the two runs

**Step 2: Write a failing test for "no loop closure"**

Add a test where the first and last coordinates are near each other but separated by an intermediate run structure, and assert no bridge is created between non-adjacent runs.

**Step 3: Write a failing test for very large adjacent gaps**

Add a test with two adjacent runs that are far apart and assert the bridge still exists and is dashed.

**Step 4: Run the focused tests to confirm failure**

Run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/TrackRenderAdapterTests
```

Expected:
- new assertions fail because bridges are not emitted yet
- if unrelated project build errors block execution, record them and continue with code changes

### Task 2: Add render-only bridge construction

**Files:**
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`

**Step 1: Add a small bridge model/helper**

Add a helper that:
- accepts ordered render runs
- iterates only adjacent pairs
- returns `RenderRouteSegment` values with `style: .dashed`
- uses exactly two points: previous last and next first
- skips empty/same-point pairs

**Step 2: Insert bridges into day snapshot output**

Update `LifelogRenderSnapshotBuilder.buildDaySnapshot` so the final far-route segments include:
- original run-derived route segments
- adjacent dashed bridge segments in stable time order

Keep footprint runs unchanged.

**Step 3: Keep all coordinate adaptation on the existing path**

Make sure bridge coordinates are passed through the same `RouteRenderingPipeline` / map adaptation behavior already used by far-route segments instead of inventing a custom drawing path.

**Step 4: Preserve render-only scope**

Verify the new bridges are not written into:
- `TrackTileSegment`
- `TrackRenderEvent`
- `LifelogStore`
- persistence files

### Task 3: Verify ordering and rendering semantics

**Files:**
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`

**Step 1: Ensure stable ordering**

Keep bridge ordering deterministic by placing a bridge immediately after the earlier run it connects, or otherwise using a clearly documented stable ordering rule.

**Step 2: Verify style-only difference**

Assert in tests that the bridge:
- uses the adjacent endpoints
- has `.dashed`
- does not alter the original solid segment coordinates

**Step 3: Run focused tests**

Run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/TrackRenderAdapterTests
```

Expected:
- focused gap-bridge tests pass
- if unrelated build failures remain, record the exact blockers

### Task 4: Run a broader regression slice around Lifelog rendering

**Files:**
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Test: `StreetStampsTests/TrackTileBuilderTests.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Run the rendering/location regression slice**

Run:
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LifelogRenderSnapshotTests -only-testing:StreetStampsTests/TrackTileBuilderTests -only-testing:StreetStampsTests/LifelogStoreBehaviorTests
```

Expected:
- no regression in gap splitting, passive ingestion, or snapshot construction
- if the suite is blocked by unrelated compile failures, capture them explicitly

### Task 5: Final verification and cleanup

**Files:**
- Modify: `docs/plans/2026-03-18-lifelog-gap-bridge-design.md` (only if wording needs correction after implementation)

**Step 1: Sanity-check product rules against implementation**

Confirm the implementation still satisfies:
- adjacent-only bridging
- no loop closure
- no non-adjacent bridging
- large adjacent gaps still dashed
- style match except dash pattern

**Step 2: Summarize blocked verification if necessary**

If unrelated build/test errors prevent full green verification, document:
- exact failing test target or compile error
- whether the new bridge logic itself compiled locally

**Step 3: Commit**

```bash
git add docs/plans/2026-03-18-lifelog-gap-bridge-design.md docs/plans/2026-03-18-lifelog-gap-bridge-implementation.md
git commit -m "docs: plan lifelog gap bridge rendering"
```
