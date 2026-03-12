# City Display Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every city display surface show the same localized name for the user's selected city hierarchy, including city cards, thumbnails, deep view, and journey lists.

**Architecture:** Keep `cityKey` as the stable identity and move all user-facing name generation behind one shared display resolver. Thread the same resolver through reverse-geocode display caching, city-card view models, deep-view title construction, and journey row presentation so locale-specific and hierarchy-specific names cannot diverge.

**Tech Stack:** Swift, SwiftUI, MapKit, CoreLocation, XCTest

---

### Task 1: Lock the regression with failing tests

**Files:**
- Create: `StreetStampsTests/CityDisplayNameResolverTests.swift`
- Modify: `StreetStampsTests/ProfileSummaryCardContentTests.swift`

**Step 1: Write the failing test**

Add focused cases that assert:
- `TW` at region/country level resolves to `台湾` in `zh-Hans`.
- `HK` at region/country level resolves to `香港` in `zh-Hans`.
- Journey-facing display chooses the same localized title as the city-card display.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityDisplayNameResolverTests`
Expected: FAIL because the shared resolver and callsites do not exist yet.

**Step 3: Write minimal implementation**

Create a shared resolver API that accepts canonical card metadata, available level names, the user's preferred level, and locale.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test ... -only-testing:StreetStampsTests/CityDisplayNameResolverTests`
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStampsTests/CityDisplayNameResolverTests.swift StreetStampsTests/ProfileSummaryCardContentTests.swift
git commit -m "test: cover unified city display rules"
```

### Task 2: Implement a single user-facing city display resolver

**Files:**
- Modify: `StreetStamps/Cityplacemarkresolver.swift`
- Modify: `StreetStamps/ReverseGeocodeService.swift`
- Modify: `StreetStamps/CityLevelPreferenceStore.swift`

**Step 1: Write the failing test**

Extend resolver tests to cover cache-key variation when locale or preferred hierarchy changes.

**Step 2: Run test to verify it fails**

Run the targeted resolver tests again.
Expected: FAIL because cache keys still only depend on `cityKey` and locale.

**Step 3: Write minimal implementation**

Add a shared display-title resolver and make reverse-geocode display cache keys include hierarchy preference scope. Handle special region-style names explicitly for `TW`, `HK`, and `MO`.

**Step 4: Run test to verify it passes**

Run the targeted resolver tests again.
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/Cityplacemarkresolver.swift StreetStamps/ReverseGeocodeService.swift StreetStamps/CityLevelPreferenceStore.swift
git commit -m "feat: unify city display title resolution"
```

### Task 3: Move every UI surface onto the shared resolver

**Files:**
- Modify: `StreetStamps/CityLibraryVM.swift`
- Modify: `StreetStamps/CityDeepView.swift`
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/ProfileSummaryCardContent.swift`
- Modify: any additional journey-row presenter discovered during implementation

**Step 1: Write the failing test**

Add/extend presentation tests to assert the same title is used for city cards and journey summaries.

**Step 2: Run test to verify it fails**

Run the targeted presentation tests.
Expected: FAIL because some views still read `name`, `displayName`, or `cityKey` directly.

**Step 3: Write minimal implementation**

Replace direct string assembly with the shared display-title API for card rows, deep-view titles, and journey rows.

**Step 4: Run test to verify it passes**

Run the same targeted tests.
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/CityLibraryVM.swift StreetStamps/CityDeepView.swift StreetStamps/MapView.swift StreetStamps/ProfileSummaryCardContent.swift
git commit -m "fix: unify city names across list and detail surfaces"
```

### Task 4: Verify the regression end to end

**Files:**
- Test: `StreetStampsTests/CityDisplayNameResolverTests.swift`
- Test: `StreetStampsTests/ProfileSummaryCardContentTests.swift`
- Test: any touched journey presentation tests

**Step 1: Run targeted verification**

Run:
- `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityDisplayNameResolverTests`
- `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/ProfileSummaryCardContentTests`

Expected: PASS

**Step 2: Run broader confidence check**

Run: `xcodebuild test -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`
Expected: PASS

**Step 3: Commit**

```bash
git add docs/plans/2026-03-10-city-display-unification-implementation.md
git commit -m "docs: record city display unification plan"
```
