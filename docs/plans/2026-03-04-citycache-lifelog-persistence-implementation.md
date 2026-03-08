# CityCache + Lifelog Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make city cache rebuild deterministic after journey load and reduce lifelog persistence IO by switching from per-point full snapshots to incremental + coalesced writes.

**Architecture:** City cache listens to journey load state transitions and rebuilds only when data is ready. Lifelog persistence splits into delta append writes for new points and debounced full snapshot checkpoints, with startup replay of pending delta lines.

**Tech Stack:** Swift, Combine, Foundation I/O, XCTest.

---

### Task 1: CityCache load-order fix

**Files:**
- Modify: `StreetStamps/CityCache.swift`
- Test: `StreetStampsTests/CityCacheLoadOrderTests.swift`

**Step 1: Write the failing test**
- Add a test that sets up `JourneyStore` with loaded journeys and asserts city cache rebuild occurs when `hasLoaded` transitions to true.

**Step 2: Run test to verify it fails**
- Run targeted test command for the new test target/scheme.

**Step 3: Write minimal implementation**
- Add a `journeyStore.$hasLoaded` subscription in `CityCache`.
- Rebuild only on `true`, and reset internal guard on `false`.

**Step 4: Run test to verify it passes**
- Re-run targeted tests.

### Task 2: Lifelog incremental + coalesced persistence

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

**Step 1: Write the failing tests**
- Add tests that verify:
  - Multiple rapid ingests preserve all points after reload.
  - Persistence path uses delta replay semantics and does not lose points.

**Step 2: Run tests to verify they fail**
- Run the new/updated tests only.

**Step 3: Write minimal implementation**
- Add delta file path and append logic.
- Load snapshot + replay delta on startup.
- Debounce full snapshot writes and clear delta after successful snapshot flush.
- Expose explicit flush for lifecycle boundaries.

**Step 4: Run tests to verify they pass**
- Re-run targeted tests.

### Task 3: App lifecycle flush integration

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`

**Step 1: Write failing test (if feasible) or add integration assertion notes**
- Ensure background/inactive path triggers both journey and lifelog flush.

**Step 2: Implement minimal change**
- Call lifelog explicit flush on background/inactive.

**Step 3: Run regression tests**
- Execute available test command and static build checks.

