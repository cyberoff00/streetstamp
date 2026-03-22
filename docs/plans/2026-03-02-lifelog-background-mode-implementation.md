# Lifelog Background Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a configurable passive Lifelog background recording mode (`高精度` / `低精度`) that only affects passive Lifelog tracking and does not change Journey tracking behavior.

**Architecture:** Introduce a dedicated passive-mode enum and settings storage, route passive-start calls through `LocationHub`, and implement two passive policies in `SystemLocationSource` with adaptive behavior for the high-precision path. Wire settings UI in `SettingsView`, and keep Journey ownership unchanged by guarding passive start calls behind `!TrackingService.shared.isTracking`.

**Tech Stack:** Swift, SwiftUI, CoreLocation, UserDefaults/AppStorage, Xcodebuild.

---

### Task 1: Define Lifelog Passive Mode Model

**Files:**
- Create: `StreetStamps/LifelogBackgroundMode.swift`
- Modify: `StreetStamps/SettingsView.swift`
- Test: `StreetStampsTests/LifelogBackgroundModeTests.swift` (new test target)

**Step 1: Write the failing test**

```swift
import XCTest
@testable import StreetStamps

final class LifelogBackgroundModeTests: XCTestCase {
    func testRawValueRoundTrip() {
        XCTAssertEqual(LifelogBackgroundMode(rawValue: "highPrecision"), .highPrecision)
        XCTAssertEqual(LifelogBackgroundMode(rawValue: "lowPrecision"), .lowPrecision)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LifelogBackgroundModeTests/testRawValueRoundTrip`
Expected: FAIL due to missing type/target.

**Step 3: Write minimal implementation**

```swift
enum LifelogBackgroundMode: String, CaseIterable {
    case highPrecision
    case lowPrecision
}
```

Add display text keys accessor as needed for settings UI.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LifelogBackgroundMode.swift StreetStampsTests/LifelogBackgroundModeTests.swift
git commit -m "feat: add lifelog passive background mode model"
```

### Task 2: Add Passive Start Routing in LocationHub

**Files:**
- Modify: `StreetStamps/LocationHub.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/PassiveLifelogRoutingTests.swift`

**Step 1: Write the failing test**

```swift
final class PassiveLifelogRoutingTests: XCTestCase {
    func testStartPassiveLifelogHighPrecisionRoutesToSystemSourceHighPrecision() {
        // Inject fake source, call startPassiveLifelog(.highPrecision), assert route method invoked.
    }

    func testStartPassiveLifelogLowPrecisionRoutesToSystemSourceLowPrecision() {
        // Inject fake source, call startPassiveLifelog(.lowPrecision), assert route method invoked.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/PassiveLifelogRoutingTests`
Expected: FAIL because API does not exist.

**Step 3: Write minimal implementation**
- Add `startPassiveLifelog(mode:)` to `LocationHub`.
- Update `StreetStampsApp.ensurePassiveLocationTrackingIfNeeded()` to read `@AppStorage` mode and call new API.
- Guard with `!TrackingService.shared.isTracking`.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/LocationHub.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/PassiveLifelogRoutingTests.swift
git commit -m "feat: route passive lifelog startup by configured mode"
```

### Task 3: Implement SystemLocationSource Passive Low Precision Policy

**Files:**
- Modify: `StreetStamps/SystemLocationSource.swift`
- Test: `StreetStampsTests/SystemLocationSourcePassiveModeTests.swift`

**Step 1: Write the failing test**

```swift
final class SystemLocationSourcePassiveModeTests: XCTestCase {
    func testStartPassiveLowPrecisionEnablesBackgroundAndSLCVisit() {
        // Assert expected manager knobs and started services.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/SystemLocationSourcePassiveModeTests/testStartPassiveLowPrecisionEnablesBackgroundAndSLCVisit`
Expected: FAIL because method missing.

**Step 3: Write minimal implementation**
- Add `startPassiveLowPrecision()`.
- Apply policy: background allowed, paused automatically true, SLC + Visit on, no high-frequency continuous updates by default.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SystemLocationSource.swift StreetStampsTests/SystemLocationSourcePassiveModeTests.swift
git commit -m "feat: add passive low precision lifelog location policy"
```

### Task 4: Implement SystemLocationSource Passive High Precision Adaptive Policy

**Files:**
- Modify: `StreetStamps/SystemLocationSource.swift`
- Test: `StreetStampsTests/SystemLocationSourcePassiveModeTests.swift`

**Step 1: Write the failing test**

```swift
final class SystemLocationSourcePassiveModeTests: XCTestCase {
    func testStartPassiveHighPrecisionStartsContinuousAndFallbackServices() {
        // Assert continuous + SLC + Visit enabled.
    }

    func testPassiveHighPrecisionDropsToCalmerSettingsWhenStationary() {
        // Feed stationary-like updates, assert reduced desiredAccuracy/distanceFilter.
    }

    func testPassiveHighPrecisionRestoresWhenMovementResumes() {
        // Feed movement update, assert return to high-precision profile.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/SystemLocationSourcePassiveModeTests`
Expected: FAIL because adaptive logic missing.

**Step 3: Write minimal implementation**
- Add `startPassiveHighPrecision()`.
- Track passive-state machine (`moving` / `stationaryCalmed`).
- Implement threshold-based demotion and promotion.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SystemLocationSource.swift StreetStampsTests/SystemLocationSourcePassiveModeTests.swift
git commit -m "feat: add adaptive passive high precision lifelog policy"
```

### Task 5: Add Settings UI for Background Recording Mode

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- (Optional parity) Modify: other locale files as needed
- Test: `StreetStampsTests/LifelogSettingsModePersistenceTests.swift`

**Step 1: Write the failing test**

```swift
final class LifelogSettingsModePersistenceTests: XCTestCase {
    func testBackgroundModeSelectionPersistsToUserDefaults() {
        // Simulate setting selection and verify stored key value.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/LifelogSettingsModePersistenceTests`
Expected: FAIL because setting key/UI does not exist.

**Step 3: Write minimal implementation**
- Add settings section with title: `后台记录模式`.
- Add options: `高精度` / `低精度`.
- Persist via `@AppStorage` key (single source of truth).

**Step 4: Run test to verify it passes**

Run: same `xcodebuild test ...`
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsView.swift StreetStamps/*.lproj/Localizable.strings StreetStampsTests/LifelogSettingsModePersistenceTests.swift
git commit -m "feat: add lifelog background mode setting"
```

### Task 6: Regression Verification (Journey Isolation + Build)

**Files:**
- Modify (if needed): `StreetStamps/TrackingService.swift`, `StreetStamps/StreetStampsApp.swift`
- Test: existing and new tests

**Step 1: Write the failing regression test**

```swift
final class JourneyIsolationTests: XCTestCase {
    func testPassiveModeDoesNotOverrideActiveJourneyLocationPolicy() {
        // Start journey, switch passive mode key, ensure journey strategy remains unchanged.
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/JourneyIsolationTests`
Expected: FAIL if isolation not guaranteed.

**Step 3: Write minimal implementation**
- Ensure passive start path is never called when `TrackingService.shared.isTracking == true`.
- Keep journey entry/exit behavior unchanged.

**Step 4: Run full verification**

Run:
- `xcodebuild test -scheme StreetStamps -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"`
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"`

Expected: all tests pass, build succeeds.

**Step 5: Commit**

```bash
git add StreetStamps/ StreetStampsTests/
git commit -m "feat: ship configurable passive lifelog background recording modes"
```

### Task 7: Manual Real-Device Validation

**Files:**
- No code changes expected

**Step 1: High precision run (30-60 min walk)**
- Set `后台记录模式=高精度`
- App to background/lockscreen, walk with turns
- Reopen and verify Lifelog/Globe route continuity

**Step 2: Low precision run (same route)**
- Set `后台记录模式=低精度`
- Repeat route window
- Confirm point density lower and fewer wakeups

**Step 3: Journey isolation check**
- Start Journey sport/daily and verify existing behavior unchanged

**Step 4: Document outcomes**
- Record observed continuity and battery deltas in a short QA note

**Step 5: Commit QA note (if created)**

```bash
git add docs/
git commit -m "docs: add passive lifelog background mode validation notes"
```
