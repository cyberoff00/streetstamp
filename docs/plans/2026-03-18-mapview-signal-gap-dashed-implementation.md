# MapView Signal Gap Dashed Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make live `MapView` display dashed route bridges after meaningful tracking signal interruptions by improving gap classification in `TrackingService`.

**Architecture:** Keep the `MapView` overlay renderer unchanged and update only the live tracking classification path in `TrackingService`. The implementation should add a recovery-specific gap heuristic, preserve the existing anti-drift protections, and verify behavior through targeted unit tests that inspect published render segments.

**Tech Stack:** Swift, XCTest, MapKit, Combine

---

### Task 1: Pin down the current live gap publication behavior with tests

**Files:**
- Modify: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`
- Test: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`

**Step 1: Write the failing test**

Add a test that simulates a meaningful tracking interruption followed by a trustworthy recovery point and asserts that `renderUnifiedSegmentsForMap` contains a `.dashed` segment.

Add a second test that simulates a long elapsed time with minimal movement and asserts that no dashed segment is produced.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/TrackingServiceResumeLocationTests`

Expected: At least the new recovery-gap test fails because the current heuristic is too conservative.

**Step 3: Confirm the existing target file already provides the right harness**

Use the existing test fixture setup in `TrackingServiceResumeLocationTests` if possible rather than creating a new test class.

**Step 4: Run the focused tests again**

Run the same `xcodebuild test` command and confirm the failure is stable and attributable to the new expectations.

**Step 5: Commit**

```bash
git add StreetStampsTests/TrackingServiceResumeLocationTests.swift
git commit -m "test: cover map recovery gap rendering"
```

### Task 2: Implement recovery-oriented gap classification in TrackingService

**Files:**
- Modify: `StreetStamps/TrackingService.swift`
- Modify: `StreetStamps/MapView.swift` only if a test reveals a publication or adapter issue

**Step 1: Add a small helper for recovery-gap classification**

Create a private helper inside `TrackingService` that evaluates whether a newly accepted point should be treated as a signal-recovery gap using existing inputs such as elapsed time, distance, recent weak/drop state, and anchor movement.

Keep the helper small and deterministic so it is easy to test through the public ingest path.

**Step 2: Integrate the helper into `ingest(_:)`**

Update the section that currently computes `isGapLike` and `isMissingSegment` so recovery cases can promote a connection to `.dashed` earlier than the general migration thresholds.

Do not remove the protections that prevent tiny jitter from becoming dashed.

**Step 3: Preserve the current render publication flow**

Ensure the resulting route segments still flow through:

- `internalSegmentsForMap`
- `latestRenderUnifiedSegmentsForMap`
- `renderUnifiedSegmentsForMap`

No renderer changes should be needed if the style is classified correctly.

**Step 4: Run the focused tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/TrackingServiceResumeLocationTests`

Expected: The new recovery-gap test passes, and the no-movement protection test also passes.

**Step 5: Commit**

```bash
git add StreetStamps/TrackingService.swift StreetStampsTests/TrackingServiceResumeLocationTests.swift
git commit -m "feat: show dashed gaps after signal recovery"
```

### Task 3: Guard against regressions in nearby live-tracking behavior

**Files:**
- Modify: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`
- Test: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`

**Step 1: Add regression tests for adjacent scenarios**

Cover at least one of each:

- weak accuracy jitter that should not become dashed
- an existing large missing segment case that should remain dashed

**Step 2: Run the focused test file**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/TrackingServiceResumeLocationTests`

Expected: All tests in that file pass.

**Step 3: Run a slightly wider live-tracking slice**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests`

Expected: No regressions in related tracking tests. If the full test target is too slow, run the tracking-related subset that exercises `TrackingService`.

**Step 4: Inspect the working tree**

Run: `git status --short`

Expected: Only the intended tracking service and test files are staged or modified for this feature.

**Step 5: Commit**

```bash
git add StreetStamps/TrackingService.swift StreetStampsTests/TrackingServiceResumeLocationTests.swift
git commit -m "test: cover tracking gap regression cases"
```
