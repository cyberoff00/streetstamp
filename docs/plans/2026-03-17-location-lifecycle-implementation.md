# Location Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Change app idle location behavior so launch/foreground only perform one-shot refreshes, passive Lifelog runs only when explicitly enabled with `Always` authorization, passive sampling becomes `35m` / `70m`, and daily Journey uses a lower-power Core Location profile.

**Architecture:** Split location behavior into three clear lifecycles: one-shot bootstrap refresh, explicit passive Lifelog runtime, and Journey-owned active tracking. Update app lifecycle routing so idle app states never auto-start continuous passive tracking. Keep Journey policies intact while making passive toggle semantics match real background behavior.

**Tech Stack:** Swift, SwiftUI, CoreLocation, Combine, XCTest, Xcodebuild.

---

### Task 1: Lock Down Idle Startup Requirements In Tests

**Files:**
- Modify: `StreetStampsTests/LocationHubCountryResolutionTests.swift`
- Create: `StreetStampsTests/LocationLifecycleRoutingTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class LocationLifecycleRoutingTests: XCTestCase {
    func test_idleLaunchRequestsSingleBootstrapRefreshInsteadOfPassiveTracking() {
        XCTFail("Implement bootstrap-vs-passive routing assertion")
    }

    func test_foregroundReturnRequestsSingleBootstrapRefreshWhenJourneyAndPassiveAreOff() {
        XCTFail("Implement foreground refresh routing assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LocationLifecycleRoutingTests`
Expected: FAIL because the routing behavior and helpers do not exist yet.

**Step 3: Write minimal implementation support**
- Add test seams or lightweight injection points needed to observe lifecycle routing.
- Keep the seam minimal and specific to location startup behavior.

**Step 4: Run test to verify it still fails for the intended reason**

Run: same `xcodebuild test ...`
Expected: FAIL due to current eager passive startup behavior.

**Step 5: Commit**

```bash
git add StreetStampsTests/LocationLifecycleRoutingTests.swift StreetStampsTests/LocationHubCountryResolutionTests.swift
git commit -m "test: add failing location lifecycle routing coverage"
```

### Task 2: Add A One-Shot Refresh API To `LocationHub`

**Files:**
- Modify: `StreetStamps/LocationHub.swift`
- Modify: `StreetStamps/SystemLocationSource.swift`
- Create: `StreetStampsTests/LocationHubSingleShotTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class LocationHubSingleShotTests: XCTestCase {
    func test_requestSingleRefreshUsesImmediateLocationWithoutStartingContinuousTracking() {
        XCTFail("Implement one-shot request assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LocationHubSingleShotTests`
Expected: FAIL because no single-shot API exists.

**Step 3: Write minimal implementation**
- Add a dedicated `LocationHub` API for one-shot refresh.
- Route it to `SystemLocationSource.requestLocation()` style behavior.
- Ensure it does not enable background updates, heading, or continuous updates.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LocationHub.swift StreetStamps/SystemLocationSource.swift StreetStampsTests/LocationHubSingleShotTests.swift
git commit -m "feat: add single-shot location refresh path"
```

### Task 3: Change App Lifecycle Routing Away From Auto-Passive Startup

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/TrackingService.swift`
- Test: `StreetStampsTests/LocationLifecycleRoutingTests.swift`

**Step 1: Write the failing test**

```swift
final class LocationLifecycleRoutingTests: XCTestCase {
    func test_idleLaunchDoesNotStartPassiveTrackingAutomatically() {
        XCTFail("Implement idle launch no-passive assertion")
    }

    func test_foregroundReturnUsesSingleRefreshWhenPassiveIsDisabled() {
        XCTFail("Implement foreground no-passive assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LocationLifecycleRoutingTests`
Expected: FAIL because startup still calls passive tracking.

**Step 3: Write minimal implementation**
- Replace eager passive startup at launch/foreground with one-shot refresh behavior.
- Keep passive startup only for the explicit passive-enabled + authorized case.
- Ensure Journey stop returns to passive only when passive should be armed; otherwise stay idle.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/TrackingService.swift StreetStampsTests/LocationLifecycleRoutingTests.swift
git commit -m "feat: route idle app lifecycle through single-shot location refresh"
```

### Task 4: Make Passive Runtime Depend On User Intent And `Always` Authorization

**Files:**
- Modify: `StreetStamps/LifelogView.swift`
- Modify: `StreetStamps/LifelogStore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Create: `StreetStampsTests/LifelogPassiveEligibilityTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class LifelogPassiveEligibilityTests: XCTestCase {
    func test_passiveDoesNotStartWithoutAuthorizedAlways() {
        XCTFail("Implement authorization gate assertion")
    }

    func test_disablingPassiveStopsPassiveRuntimeAndStorage() {
        XCTFail("Implement passive stop assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LifelogPassiveEligibilityTests`
Expected: FAIL because passive runtime is not currently gated this way.

**Step 3: Write minimal implementation**
- Make passive enablement mean actual passive runtime intent.
- Gate passive startup on `authorizedAlways`.
- Ensure turning passive off stops passive runtime and prevents new passive point ingestion.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogView.swift StreetStamps/LifelogStore.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/LifelogPassiveEligibilityTests.swift
git commit -m "feat: gate passive runtime on user intent and always authorization"
```

### Task 5: Reduce Passive Sampling Profiles To `35m` / `70m`

**Files:**
- Modify: `StreetStamps/SystemLocationSource.swift`
- Modify: `StreetStamps/LifelogBackgroundMode.swift`
- Create: `StreetStampsTests/SystemLocationSourcePassiveProfileTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class SystemLocationSourcePassiveProfileTests: XCTestCase {
    func test_highPrecisionPassiveUses35MeterDistanceFilter() {
        XCTFail("Implement 35m profile assertion")
    }

    func test_lowPrecisionPassiveUses70MeterDistanceFilter() {
        XCTFail("Implement 70m profile assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/SystemLocationSourcePassiveProfileTests`
Expected: FAIL because passive profiles are still denser.

**Step 3: Write minimal implementation**
- Set passive high precision to a `35m` distance filter.
- Set passive low precision to a `70m` distance filter.
- Remove or simplify any adaptive passive logic that conflicts with these fixed product rules.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SystemLocationSource.swift StreetStamps/LifelogBackgroundMode.swift StreetStampsTests/SystemLocationSourcePassiveProfileTests.swift
git commit -m "feat: simplify passive profiles to 50m and 100m"
```

### Task 6: Relax Daily Journey Base Location Profile

**Files:**
- Modify: `StreetStamps/SystemLocationSource.swift`
- Modify: `StreetStampsTests/SystemLocationSourcePassiveProfileTests.swift` or split into a dedicated daily-profile test file

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class SystemLocationSourceDailyProfileTests: XCTestCase {
    func test_dailyJourneyUsesNearestTenMetersAccuracy() {
        XCTFail("Implement daily desiredAccuracy assertion")
    }

    func test_dailyJourneyUses15MeterDistanceFilter() {
        XCTFail("Implement daily distanceFilter assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/SystemLocationSourceDailyProfileTests`
Expected: FAIL because daily profile is still denser.

**Step 3: Write minimal implementation**
- Change `startHighPowerDaily()` to:
  - `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`
  - `distanceFilter = 15`
- Keep Journey ownership and mode routing otherwise unchanged.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SystemLocationSource.swift StreetStampsTests/SystemLocationSourceDailyProfileTests.swift
git commit -m "feat: relax daily journey location profile"
```

### Task 7: Verify Journey Isolation And Build Health

**Files:**
- Modify: `StreetStampsTests/JourneyIsolationTests.swift` (create if absent)
- Test: existing and new suites

**Step 1: Write the failing regression test**

```swift
import XCTest
@testable import StreetStamps

final class JourneyIsolationTests: XCTestCase {
    func test_activeJourneyStillOwnsContinuousTrackingWhenPassiveIsEnabled() {
        XCTFail("Implement journey ownership assertion")
    }

    func test_stoppingJourneyReturnsToIdleWhenPassiveIsNotEligible() {
        XCTFail("Implement post-journey idle assertion")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/JourneyIsolationTests`
Expected: FAIL until ownership boundaries are explicit.

**Step 3: Write minimal implementation**
- Preserve Journey start/foreground/background tracking ownership.
- After Journey stop, branch to passive runtime only when passive is enabled and authorized; otherwise leave idle.

**Step 4: Run full verification**

Run:
- `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"`
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"`

Expected: all tests pass and the app builds cleanly.

**Step 5: Commit**

```bash
git add StreetStampsTests/JourneyIsolationTests.swift StreetStamps/StreetStampsApp.swift StreetStamps/TrackingService.swift
git commit -m "test: verify journey tracking remains isolated from idle passive lifecycle"
```
