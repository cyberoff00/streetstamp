# Lifelog Async Render Snapshot Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move `LifelogView` from synchronous render-time fallback computation to an async snapshot pipeline that keeps the page responsive.

**Architecture:** Extract a render snapshot model plus pure/predictable builder logic, drive refreshes from a single scheduling path, and atomically replace snapshot state after background computation completes. Preserve existing visual semantics and fallback order while removing heavy render work from `body`.

**Tech Stack:** Swift, SwiftUI, MapKit, XCTest, structured concurrency

---

### Task 1: Add failing snapshot tests

**Files:**
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`

**Step 1: Write the failing test**

- Add coverage for:
  - near-mode snapshot using tile data before unified fallback
  - far-mode snapshot producing route segments and center from one snapshot
  - generation gating rejecting stale completions

**Step 2: Run test to verify it fails**

- Run the new test target selection and confirm failure is due to missing snapshot types/behavior.

### Task 2: Extract snapshot types and pure builder logic

**Files:**
- Create: `StreetStamps/LifelogRenderSnapshot.swift`
- Modify: `StreetStamps/LifelogView.swift`
- Test: `StreetStampsTests/LifelogRenderSnapshotTests.swift`

**Step 1: Write minimal implementation**

- Introduce:
  - `LifelogRenderSnapshot`
  - request/input structs
  - builder functions for path coords, far route segments, footprint runs, and selected-day center
  - generation helper for stale-result protection

**Step 2: Run tests to verify pass**

- Re-run `LifelogRenderSnapshotTests`.

### Task 3: Integrate async snapshot refresh into `LifelogView`

**Files:**
- Modify: `StreetStamps/LifelogView.swift`

**Step 1: Replace synchronous render helpers with snapshot state**

- Add:
  - `@State private var renderSnapshot`
  - `@State private var renderTask`
  - `@State private var renderGeneration`
- Route all relevant state changes through `scheduleRenderSnapshotRefresh()`.

**Step 2: Keep current UI behavior**

- Preserve:
  - robot marker
  - footprint rendering
  - far-route rendering
  - selected-day recentering

**Step 3: Run focused verification**

- Confirm the app compiles and the targeted tests remain green.

### Task 4: Verify integration

**Files:**
- Modify: `docs/plans/2026-03-06-lifelog-globe-stability-implementation.md`

**Step 1: Run focused tests**

- Run the snapshot tests plus existing render adapter tests.

**Step 2: Run build verification**

- Build the app target to catch SwiftUI/concurrency integration regressions.

**Step 3: Update tracking note**

- Record that `LifelogView` now uses async snapshot rendering and note any remaining debounce/manual QA risks.
