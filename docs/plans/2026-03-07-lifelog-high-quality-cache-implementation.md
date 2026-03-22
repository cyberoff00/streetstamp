# Lifelog High-Quality Cache Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an in-memory high-quality segmented render cache for `Lifelog`, remove visual downgrade paths, and prewarm the newest 7 days without hurting foreground responsiveness.

**Architecture:** Build one segmented day snapshot model as the geometry source of truth, derive viewport render snapshots from it, and manage warmup / dirty-day refreshes through a dedicated cache coordinator. `LifelogView` becomes a cache consumer that only applies high-quality results and never re-enters low-quality fallback rendering.

**Tech Stack:** Swift, SwiftUI, MapKit, structured concurrency, XCTest

---

### Task 1: Add failing cache and segmentation tests

**Files:**
- Modify: `StreetStampsTests/LifelogRenderSnapshotTests.swift`
- Create: `StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift`

**Step 1: Write the failing test**

- Add coverage for:
  - warmup order `today -> yesterday -> previous 5 days`
  - no-downgrade decisions
  - segmented render derivation preserving separate runs
  - unsafe today append forcing rebuild

**Step 2: Run test to verify it fails**

- Attempt the focused test run or note existing scheme limitations if the project still has no runnable test action.

### Task 2: Extract cache keys, day snapshot model, and coordinator logic

**Files:**
- Create: `StreetStamps/LifelogRenderCacheCoordinator.swift`
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`
- Modify: `StreetStamps/TrackRenderAdapter.swift`
- Test: `StreetStampsTests/LifelogRenderCacheCoordinatorTests.swift`

**Step 1: Write minimal implementation**

- Introduce:
  - day snapshot keys
  - viewport cache keys
  - high-quality segmented day snapshot model
  - viewport render derivation helpers
  - no-downgrade decision helper
  - today dirty / coalesced refresh scheduler

**Step 2: Run tests to verify pass**

- Re-run focused logic tests if test execution is available.

### Task 3: Wire app-level warmup and dirty-day invalidation

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/JourneyStore.swift`

**Step 1: Hook coordinator into startup**

- Prewarm recent 7 day snapshots after tile data is ready.
- Cancel or deprioritize warmup when explicit `Lifelog` work arrives.

**Step 2: Hook revision changes**

- Mark only `today` dirty on passive revision changes.
- Requeue relevant days conservatively on journey revision changes.

### Task 4: Convert `LifelogView` to cache-backed rendering

**Files:**
- Modify: `StreetStamps/LifelogView.swift`

**Step 1: Replace old fallback scheduling**

- Read from day / viewport cache.
- Keep current high-quality result while new viewport work runs.
- Show only the base map when switching to an uncached day.

**Step 2: Keep current UX behavior**

- Preserve robot marker, current-location display, day recentering, and map interactions.
- Ensure near and far mode derive from the same segmented snapshot.

### Task 5: Verify build and integration

**Files:**
- Modify: `docs/plans/2026-03-07-lifelog-high-quality-cache-implementation.md`

**Step 1: Run focused tests if possible**

- Run cache / render logic tests or document the test-target limitation.

**Step 2: Run build verification**

- Build the iOS app target and confirm the refactor compiles.

**Step 3: Update implementation notes**

- Record any remaining QA risks around cache cold-starts and viewport bucketing.
