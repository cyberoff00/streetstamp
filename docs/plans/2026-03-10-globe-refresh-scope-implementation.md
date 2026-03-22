# Globe Refresh Scope Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Globe refresh only on first page enter, completed journey save/end, and passive lifelog day rollover.

**Architecture:** Add a dedicated Globe refresh coordinator with a published revision counter and explicit trigger API. Emit refreshes from journey completion and passive day rollover code paths, and update Globe UI to observe only that event instead of low-level store revisions.

**Tech Stack:** Swift, SwiftUI, XCTest, NotificationCenter-free coordinator state

---

### Task 1: Extend Globe refresh coordinator and tests

**Files:**
- Modify: `StreetStamps/GlobeRefreshCoordinator.swift`
- Modify: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Write the failing test**

Add tests for:
- revision increments when a refresh is requested
- optional refresh reasons stay scoped to business events

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests`
Expected: FAIL because the coordinator API does not exist yet.

**Step 3: Write minimal implementation**

Add a main-actor observable coordinator with:
- shared singleton
- `revision`
- `requestRefresh(reason:)`

Keep `GlobeRefreshGate` and `GlobeRouteResolver` in place.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests`
Expected: PASS

### Task 2: Emit Globe refresh from completed journey persistence

**Files:**
- Modify: `StreetStamps/JourneyStore.swift`
- Test: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Write the failing test**

Add a test that `addCompletedJourney(_:)` increments Globe revision once.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests/test_addCompletedJourney_requestsGlobeRefresh`
Expected: FAIL because no refresh is emitted yet.

**Step 3: Write minimal implementation**

Request Globe refresh in the completed-journey path after the in-memory update is accepted.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests/test_addCompletedJourney_requestsGlobeRefresh`
Expected: PASS

### Task 3: Emit Globe refresh only on passive day rollover

**Files:**
- Modify: `StreetStamps/LifelogStore.swift`
- Test: `StreetStampsTests/GlobeRefreshCoordinatorTests.swift`

**Step 1: Write the failing tests**

Add tests for:
- same-day passive append does not request Globe refresh
- cross-day passive append requests Globe refresh once

**Step 2: Run test to verify they fail**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests`
Expected: FAIL because LifelogStore does not emit Globe refreshes yet.

**Step 3: Write minimal implementation**

Detect whether newly appended passive points introduced a new day key compared with pre-append state. Emit Globe refresh only when a new day is inserted.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/GlobeRefreshCoordinatorTests`
Expected: PASS

### Task 4: Collapse Globe UI onto the coordinator signal

**Files:**
- Modify: `StreetStamps/GlobeViewScreen.swift`
- Modify: `StreetStamps/MapboxGlobeView.swift`

**Step 1: Write the failing test**

Use existing coordinator/unit coverage as the regression net for the new refresh policy and verify manually in simulator after code change.

**Step 2: Write minimal implementation**

- Remove Globe screen listeners for low-level revisions.
- Refresh prepared globe data on first page instance entry and on coordinator revision changes.
- Remove render-trigger `onChange` handlers and debug prints from `MapboxGlobeView`.
- Keep style-load handling required for the initial draw.

**Step 3: Run focused verification**

Run the Globe refresh tests and launch the app to verify:
- Globe loads on first entry
- Globe updates after finishing a journey
- Globe updates after passive day rollover

**Step 4: Run broader verification**

Run the relevant test target and confirm no Globe route resolution regressions.
