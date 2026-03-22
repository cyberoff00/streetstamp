# Lifelog Footprint Shape Sampling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `Lifelog`'s fixed-distance near-mode footprint sampling with a shape-aware sampler that preserves route silhouette while keeping footprint markers sparse and readable.

**Architecture:** Keep the existing segmented day snapshot and viewport planner pipeline, but change footprint derivation into a two-stage process: extract route-shaping anchors, then add a small bounded number of fill points between anchors. The viewport planner remains the final anti-collision layer instead of being the main simplification mechanism.

**Tech Stack:** Swift, SwiftUI, MapKit, CoreLocation, XCTest

---

### Task 1: Add failing sampler coverage

**Files:**
- Modify: `StreetStampsTests/TrackRenderAdapterTests.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write the failing test**

- Add tests that describe the new footprint behavior:
  - preserves start and end points
  - keeps obvious turns instead of flattening them away
  - keeps long straight routes sparse
  - does not sample across gap breaks
  - preserves enough points for a simple loop silhouette

**Step 2: Run test to verify it fails**

- Run the focused sampler tests first.
- Expected: current fixed-distance sampler fails one or more shape-preservation expectations.

**Step 3: Commit**

```bash
git add StreetStampsTests/TrackRenderAdapterTests.swift
git commit -m "test: define shape-aware lifelog footprint sampling"
```

### Task 2: Implement shape-anchor extraction

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write minimal implementation**

- Expand `LifelogFootprintSampler` so it can:
  - identify turn anchors from heading changes
  - retain route endpoints
  - insert straight-span anchors when a segment grows beyond the maximum allowed length
  - preserve gap-break semantics

**Step 2: Run tests to verify pass**

- Re-run the new shape-anchor tests.
- Expected: turn preservation and gap-break tests pass, even if fill behavior still needs work.

**Step 3: Commit**

```bash
git add StreetStamps/LifelogView.swift StreetStampsTests/TrackRenderAdapterTests.swift
git commit -m "feat: preserve lifelog route shape in footprint anchors"
```

### Task 3: Implement bounded rhythm fill

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/LifelogRenderSnapshot.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write minimal implementation**

- Add bounded fill-point generation between consecutive anchors:
  - no fill for short spans
  - 1 fill point for medium spans
  - 2-3 fill points for long spans
  - hard cap on per-span fill count
- Keep the existing `buildFootprintGroup` call shape intact so the rest of the render snapshot pipeline does not need structural changes.

**Step 2: Run tests to verify pass**

- Re-run the focused sampler tests.
- Expected: straight-route sparsity and loop-shape tests now pass.

**Step 3: Commit**

```bash
git add StreetStamps/LifelogView.swift StreetStamps/LifelogRenderSnapshot.swift StreetStampsTests/TrackRenderAdapterTests.swift
git commit -m "feat: add rhythmic fill to lifelog footprints"
```

### Task 4: Retune viewport marker planning for the new sampler

**Files:**
- Modify: `StreetStamps/LifelogFootprintRenderPlanner.swift`
- Test: `StreetStampsTests/TrackRenderAdapterTests.swift`

**Step 1: Write minimal implementation**

- Adjust LOD spacing and/or max-marker tuning only if needed so preserved anchor points survive planner culling.
- Keep the planner's role limited to viewport clipping, anti-collision, and marker-count control.

**Step 2: Run tests to verify pass**

- Re-run sampler tests and any existing footprint/planner tests.
- Expected: no regressions in gap handling or endpoint preservation.

**Step 3: Commit**

```bash
git add StreetStamps/LifelogFootprintRenderPlanner.swift StreetStampsTests/TrackRenderAdapterTests.swift
git commit -m "tune: rebalance viewport footprint planner for shape-aware sampling"
```

### Task 5: Verify build and integration

**Files:**
- Modify: `docs/plans/2026-03-12-lifelog-footprint-shape-sampling-implementation.md`

**Step 1: Run focused tests if possible**

- Run the footprint sampler tests first.
- If project test execution is limited, record the limitation in the implementation notes.

**Step 2: Run build verification**

- Build the app target to confirm the sampler and render snapshot changes compile cleanly.

**Step 3: Update implementation notes**

- Record the final tuning values used for:
  - turn threshold
  - maximum straight-span anchor distance
  - fill-point thresholds
  - any planner separation changes

**Step 4: Commit**

```bash
git add docs/plans/2026-03-12-lifelog-footprint-shape-sampling-implementation.md
git commit -m "docs: capture lifelog footprint sampling verification notes"
```
