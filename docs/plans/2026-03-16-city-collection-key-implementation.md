# City Collection Key Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Introduce a stable collection-key aggregation layer so local collection views, Journey Memory, and friend mirror screens can display merged cities without changing underlying journey city identities.

**Architecture:** Keep `cityKey` as the identity key stored on journeys and cloud payloads. Add a lightweight resolver layer that maps raw `cityKey` values to `collectionKey` values for UI aggregation, and centralize display-title lookup through the same layer so merged cards and grouped lists render consistent names.

**Tech Stack:** Swift, SwiftUI, XCTest, existing city display and journey presentation code.

---

### Task 1: Add failing tests for collection-key resolution and collection aggregation

**Files:**
- Modify: `StreetStampsTests/CityDisplayNameResolverTests.swift`

**Step 1: Write the failing tests**

- Add a test that expects a configured raw `cityKey` to resolve to a merged `collectionKey`.
- Add a test that expects `CityLibraryVM.buildCities(...)` to merge two cached cities into one output city when their `cityKey`s map to the same `collectionKey`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityDisplayNameResolverTests`

Expected: FAIL because the collection-key resolver behavior does not exist yet.

### Task 2: Add minimal collection-key and display-title resolver layer

**Files:**
- Modify: `StreetStamps/CityLibraryVM.swift`

**Step 1: Write minimal implementation**

- Add `CityCollectionResolver` with:
  - runtime overrides for tests
  - `resolveCollectionKey(cityKey:)`
  - `resolveCollectionKey(for:)`
- Add `CityDisplayResolver` with:
  - `title(for:fallbackTitle:)`
  - lookup through the collection resolver’s configured merged title

**Step 2: Run tests**

Run the same focused test command and make sure the resolver tests pass.

### Task 3: Update Journey Memory grouping to use collection keys

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`

**Step 1: Add a small pure helper**

- Extract city-group construction into a helper that resolves raw `cityKey` to `collectionKey`.
- Keep raw journey data untouched; only grouping keys and display titles change.

**Step 2: Verify**

- Add/extend tests if needed once the helper is reachable.

### Task 4: Update Collection tab city cards to group by collection key

**Files:**
- Modify: `StreetStamps/CityLibraryVM.swift`

**Step 1: Change `buildCities(...)`**

- Group cached cities by `collectionKey`
- Merge journeys, exploration counts, and memory counts
- Use the merged `collectionKey` as the UI city id

**Step 2: Run focused tests**

Re-run the city resolver test target and confirm the merge case stays green.

### Task 5: Verify and summarize

**Files:**
- None

**Step 1: Run focused tests**

Run the targeted `xcodebuild test` command for the touched test file.

**Step 2: Record follow-up**

- Friend mirror aggregation
- Wider display-title call-site migration
- Cloud upload/download alignment
