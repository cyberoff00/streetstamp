# Lifelog / Globe Stability and Fidelity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Lifelog and Globe share one stable, high-fidelity, upgrade-safe route pipeline with strict segmentation, durable mood persistence, and lower-cost passive sampling.

**Architecture:** Keep journey and passive stores as truth layers, build a unified render event stream and strict segment pipeline on top, and treat tiles / indexes / footprints as derived caches only. Implement survivability fixes first so rebuilds and upgrades can never hide source-backed user data, then move rendering and passive sampling to the new semantics incrementally.

**Tech Stack:** Swift, SwiftUI, XCTest, DispatchQueue, file-backed caches

---

### Task 1: Lock in source survivability regressions

**Files:**
- Modify: `StreetStampsTests/LifelogStoreBehaviorTests.swift`
- Modify: `StreetStampsTests/LifelogMigrationServiceTests.swift`
- Modify: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write failing tests**

- Add tests for:
  - mood survives rebuild / reload when only side-file data exists
  - mood survives guest/account recovery
  - source-backed history still renders when derived caches are absent
  - route segments never reconnect across source or discontinuity boundaries

**Step 2: Run tests to verify RED**

Run targeted `xcodebuild test` commands for the new cases and confirm failures are for the intended missing behavior.

**Step 3: Implement minimal fixes**

- No production code in this task beyond the minimum needed to satisfy the failing survivability tests.

**Step 4: Re-run tests to verify GREEN**

- Re-run the same targeted tests and confirm they pass.

### Task 2: Fix mood durability and recovery gaps

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/GuestDataRecoveryService.swift`
- Modify: `StreetStamps/LifelogMigrationService.swift`
- Modify: `StreetStamps/DataMigrator.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`
- Test: `StreetStampsTests/LifelogMigrationServiceTests.swift`

**Step 1: Write the failing test**

- Cover recovery / migration of `lifelog_mood.json` and embedded `moodByDay`.

**Step 2: Run test to verify it fails**

- Target only the new mood recovery cases.

**Step 3: Write minimal implementation**

- Ensure recovery/migration paths copy or merge mood side-file state.
- Make load resilient when the primary route payload decodes partially but mood side-file remains valid.

**Step 4: Run tests to verify pass**

- Re-run mood-related targeted tests.

### Task 3: Add unified render event provider

**Files:**
- Create: `StreetStamps/UnifiedLifelogRenderProvider.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/GlobeViewScreen.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write failing tests**

- Verify journey and passive events merge into one ordered stream with stable source tagging.

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Introduce a provider that merges both stores without changing truth ownership.

**Step 4: Run tests to verify GREEN**

### Task 4: Introduce strict segmentation rules

**Files:**
- Modify: `StreetStamps/TrackRenderAdapter.swift`
- Modify: `StreetStamps/TrackTileBuilder.swift`
- Modify: `StreetStamps/RouteRendering.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`
- Test: `StreetStampsTests/TrackTileBuilderTests.swift`

**Step 1: Write failing tests**

- Cover segment breaks for:
  - source changes
  - large time gaps
  - large spatial jumps
  - weak-GPS / uncertain points
  - stationary-to-moving restart

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Build strict segment boundaries and ensure no path reconnect logic survives.

**Step 4: Run tests to verify GREEN**

### Task 5: Improve Lifelog fidelity and footprint projection

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/TrackRenderAdapter.swift`
- Modify: `StreetStamps/RouteRendering.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`
- Test: `StreetStampsTests/LifelogRenderModeSelectorTests.swift`

**Step 1: Write failing tests**

- Verify near-mode footprint projection follows the high-fidelity route shape.
- Verify far/mid mode no longer over-straightens local turns in covered scenarios.

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Replace current over-simplified near-path fallback with shape-preserving segment reads and footprint projection on those runs.

**Step 4: Run tests to verify GREEN**

### Task 6: Unify Globe reads with the same semantics

**Files:**
- Modify: `StreetStamps/GlobeViewScreen.swift`
- Modify: `StreetStamps/MapboxGlobeView.swift`
- Modify: `StreetStamps/TrackRenderAdapter.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write failing tests**

- Verify Globe consumes the same unified segment semantics as Lifelog, not a divergent passive-only fallback.

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Move Globe route preparation to the unified provider / segment pipeline.

**Step 4: Run tests to verify GREEN**

### Task 7: Add passive motion and weak-GPS gating

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/LocationHub.swift`
- Modify: `StreetStamps/SystemLocationSource.swift`
- Modify: `StreetStamps/LifelogBackgroundMode.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write failing tests**

- Cover:
  - no route writes while stationary
  - no route writes on weak GPS
  - uncertain-to-moving starts a new segment

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Introduce the smallest viable passive state machine and quality gating.

**Step 4: Run tests to verify GREEN**

### Task 8: Make rebuilds gradual and foreground-safe

**Files:**
- Modify: `StreetStamps/TrackTileStore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/GlobeViewScreen.swift`
- Test: `StreetStampsTests/TrackTileBuilderTests.swift`

**Step 1: Write failing tests**

- Cover source-visible fallback when cache is invalid / absent.
- Cover prioritized incremental rebuild behavior where feasible.

**Step 2: Run tests to verify RED**

**Step 3: Write minimal implementation**

- Keep caches derived-only, allow partial rebuild state, and avoid blocking current-view reads.

**Step 4: Run tests to verify GREEN**

### Task 9: Verify and document

**Files:**
- Modify: `docs/plans/2026-03-01-product-issues-tracker.md`

**Step 1: Run focused verification**

- Run targeted tests for:
  - mood persistence / recovery
  - lifelog behavior
  - render adapter
  - tile builder

**Step 2: Run build verification**

- Build the main app target and confirm no compilation regressions.

**Step 3: Update tracker**

- Record what was fixed, what was verified, and any remaining risk.

**Step 4: Summarize residual risks**

- Note battery validation and real-device motion QA as still requiring manual measurement.
