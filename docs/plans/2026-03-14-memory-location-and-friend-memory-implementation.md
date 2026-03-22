# Memory Location And Friend Memory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make memory location durable and non-blocking under weak GPS, upload explicit memory coordinates for shared journeys, and restore tappable friend memory photo details.

**Architecture:** Memory save becomes a two-phase process: content persists immediately, while location is resolved from a prioritized source list and may remain pending for later backfill. Journey completion finalizes pending locations without blocking the user, backend DTOs carry explicit memory coordinates, and friend memory interactions consume those fields in a read-only detail flow.

**Tech Stack:** Swift, SwiftUI, MapKit, Codable DTOs, existing JourneyStore/TrackingService/FriendsHub architecture, XCTest.

---

### Task 1: Add memory location state to the model

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/JourneyRouteCodableTests.swift`

**Step 1: Write the failing test**

Add tests proving `JourneyMemory` round-trips new `locationStatus` and `locationSource` fields while remaining backward compatible when fields are absent.

**Step 2: Run test to verify it fails**

Run: target the new codable tests with Xcode test/build workflow already used in the repo.
Expected: compile/test failure because the fields do not exist yet.

**Step 3: Write minimal implementation**

Add small enums for memory location status/source, extend `JourneyMemory` with optional or defaulted fields, and update manual `Codable` implementation to decode missing values safely.

**Step 4: Run test to verify it passes**

Run the same codable-focused tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `feat: add memory location status metadata`

### Task 2: Introduce a reusable memory location resolver

**Files:**
- Modify: `StreetStamps/TrackingService.swift`
- Modify: `StreetStamps/MapView.swift`
- Create or modify: `StreetStamps/MemoryLocationResolver.swift` or colocated helper file
- Test: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`
- Test: `StreetStampsTests/JourneyMemoryMapCoordinateResolverTests.swift`
- Create: `StreetStampsTests/MemoryLocationResolverTests.swift`

**Step 1: Write the failing test**

Add tests for source priority:
- fresh accurate live GPS wins
- stale/weak live GPS falls back to nearest journey track point by timestamp
- if track is unavailable, use last known location
- if nothing is available, result is pending

**Step 2: Run test to verify it fails**

Run only the new resolver tests.
Expected: FAIL because resolver behavior does not exist.

**Step 3: Write minimal implementation**

Implement a small resolver that accepts:
- memory timestamp
- current live location
- last known location
- journey coordinates plus derived timestamps

Return resolved coordinate, status, and source.

**Step 4: Run test to verify it passes**

Run resolver-focused tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `feat: add memory location resolver`

### Task 3: Update memory save flow so content always persists

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MemorySaveBehaviorTests.swift` or create a new focused test file

**Step 1: Write the failing test**

Add tests showing:
- creating a memory with weak/missing GPS still saves the memory record
- saved memory is marked pending when no reliable coordinate is available
- editing memory content does not overwrite an already resolved coordinate

**Step 2: Run test to verify it fails**

Run the new save-behavior tests.
Expected: FAIL.

**Step 3: Write minimal implementation**

Replace the direct `guard let loc = tracking.userLocation else { return }` create path with resolver-based save logic. Content should be appended immediately; coordinate/status/source come from the resolver result.

**Step 4: Run test to verify it passes**

Run the same save-behavior tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `feat: save memories without blocking on gps`

### Task 4: Finalize pending memories when ending a journey

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/JourneyFinalizer.swift`
- Test: `StreetStampsTests/JourneySaveCompletionTests.swift`
- Create: `StreetStampsTests/MemoryLocationFinalizationTests.swift`

**Step 1: Write the failing test**

Add tests showing:
- ending a journey does not fail when pending memories exist
- pending memories are backfilled from nearest journey track points when available
- memories remain pending only if no usable coordinate source exists

**Step 2: Run test to verify it fails**

Run the new finalization tests.
Expected: FAIL.

**Step 3: Write minimal implementation**

Before or during finalization, sweep pending memories through the resolver using final journey coordinates and last valid location. Never gate finish on success.

**Step 4: Run test to verify it passes**

Run the same tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `feat: finalize pending memory locations on journey end`

### Task 5: Make map and share rendering resilient to pending memory locations

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/CityDeepView.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/SharingCard.swift`
- Test: `StreetStampsTests/JourneyMemoryMapCoordinateResolverTests.swift`
- Create: `StreetStampsTests/SharingCardFallbackTests.swift`

**Step 1: Write the failing test**

Add tests proving:
- pending memories do not collapse unrelated pins into one bogus location
- share-card rendering can still produce a non-placeholder result when route/memory location completeness is partial

**Step 2: Run test to verify it fails**

Run the mapping/share fallback tests.
Expected: FAIL.

**Step 3: Write minimal implementation**

Ensure map/grouping code respects memory status and avoids pretending pending memories have exact locations. Update sharing card generation to degrade to partial/non-map layouts instead of a broken placeholder.

**Step 4: Run test to verify it passes**

Run the same tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `fix: degrade gracefully for incomplete memory location data`

### Task 6: Upload explicit memory coordinates to the backend

**Files:**
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/JourneyCloudMigrationService.swift`
- Modify: `StreetStamps/SocialGraphStore.swift`
- Test: `StreetStampsTests/JourneyCloudMigrationServiceTests.swift`
- Create: `StreetStampsTests/FriendSharedJourneyCodableTests.swift`

**Step 1: Write the failing test**

Add tests showing:
- uploaded backend memory DTO includes latitude/longitude/locationStatus when available
- decoding remote shared journeys preserves explicit memory coordinates when present
- old payloads without coordinates still decode successfully

**Step 2: Run test to verify it fails**

Run backend DTO focused tests.
Expected: FAIL.

**Step 3: Write minimal implementation**

Extend backend/shared DTOs with optional memory coordinate fields and update encode/decode paths. Use memory-owned coordinates instead of inferring from route index whenever remote coordinates are present.

**Step 4: Run test to verify it passes**

Run the same DTO tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `feat: sync explicit memory coordinates`

### Task 7: Fix friend memory pin photo opening

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Test: `StreetStampsTests/FriendMemoryInteractionTests.swift`

**Step 1: Write the failing test**

Add tests proving:
- tapping a friend memory pin opens a read-only detail surface
- detail rendering uses `remoteImageURLs`
- photos are visible without edit controls

**Step 2: Run test to verify it fails**

Run the new friend interaction tests.
Expected: FAIL.

**Step 3: Write minimal implementation**

Wire friend memory pin taps to the read-only memory detail path and ensure the detail/photo component loads remote images for shared memories.

**Step 4: Run test to verify it passes**

Run the same tests.
Expected: PASS.

**Step 5: Commit**

Commit message: `fix: open friend memory photos from map pins`

### Task 8: Verification pass

**Files:**
- Modify only if verification exposes regressions

**Step 1: Run targeted test suite**

Run all tests added/updated in Tasks 1-7.

**Step 2: Run broader regression coverage**

Run nearby existing suites covering journeys, render snapshots, sharing cards, and friend/shared flows.

**Step 3: Perform one manual scenario check**

Manual checks:
- save a memory under weak GPS
- end a journey with a pending memory
- open a friend memory pin with remote photos

**Step 4: Fix any regression and re-run**

Keep changes minimal and rerun failing checks.

**Step 5: Commit**

Commit message: `test: verify memory location and friend memory flows`
