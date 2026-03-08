# Lifelog Historical Lazy Load Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep historical lifelog data, show recent 7 days by default, and speed up date switching via background day index.

**Architecture:** `points` remains authoritative full-history source. `coordinates` becomes a recent-window projection for default rendering. Day-specific rendering stays API-compatible (`mapPolyline(day:)`) and uses lazy cache with asynchronous day-index prebuild.

**Tech Stack:** Swift, XCTest, MainActor concurrency, DispatchQueue utility workers.

---

### Task 1: Red tests for desired behavior

**Files:**
- Modify: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

1. Add/update tests asserting load no longer prunes yesterday data.
2. Add test asserting default `coordinates` only contains recent 7-day window while `mapPolyline(day: olderDay)` still returns data.
3. Run targeted tests and confirm RED.

### Task 2: LifelogStore behavior changes

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`

1. Remove load-time prune-to-today execution path.
2. Add recent-window projection helper (`recentWindowStart`, `recentCoordinates`).
3. Set `coordinates` from recent-window projection when applying loaded state.
4. Add background day index build task that pre-populates `dayCoordsCache`.
5. Replace heavy `DateFormatter` day-key generation with component-based day key.

### Task 3: Verify GREEN and regressions

**Files:**
- Test: `StreetStampsTests/LifelogStoreBehaviorTests.swift`

1. Run targeted lifelog behavior tests.
2. Run tile/day-related tests to ensure no regression in day filtering.
3. If failing, minimally adjust implementation only.

### Task 4: Document outcome

**Files:**
- Modify: `docs/plans/2026-03-01-product-issues-tracker.md`

1. Append note in remarks for the lifelog/history issue with completion date and validation command summary.

