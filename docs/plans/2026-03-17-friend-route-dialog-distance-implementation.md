# Friend Route Dialog Distance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show two sequential English speech bubbles in the read-only friend journey detail view, using the straight-line distance from the user's current location to the friend's journey endpoint.

**Architecture:** Keep distance math and text formatting in a tiny pure presentation helper so the view can stay declarative and the behavior can be regression-tested. Feed the helper from `JourneyRouteDetailView` using `LocationHub.currentLocation` with `lastKnownLocation` as fallback, then pass the formatted string into the existing animated friend overlay and split the message into two timed bubbles.

**Tech Stack:** SwiftUI, CoreLocation, XCTest

---

### Task 1: Add regression tests for distance text

**Files:**
- Create: `StreetStampsTests/FriendJourneyDistancePresentationTests.swift`
- Modify: `StreetStamps/JourneyRouteDetailView.swift`

**Step 1: Write the failing test**

```swift
func test_makeDistanceText_usesStraightLineDistanceToJourneyEndpoint() {
    let user = CLLocation(latitude: 51.5007, longitude: -0.1246)
    let friendEnd = CLLocationCoordinate2D(latitude: 51.5014, longitude: -0.1419)

    let text = FriendJourneyDistancePresentation.makeDistanceText(
        currentLocation: user,
        lastKnownLocation: nil,
        journeyEndCoordinate: friendEnd
    )

    XCTAssertEqual(text, "1.2 km")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/FriendJourneyDistancePresentationTests`

Expected: FAIL because the helper does not exist yet.

**Step 3: Write minimal implementation**

```swift
enum FriendJourneyDistancePresentation {
    static func makeDistanceText(...) -> String { ... }
}
```

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new tests pass.

### Task 2: Connect distance text to the read-only journey detail view

**Files:**
- Modify: `StreetStamps/JourneyRouteDetailView.swift`

**Step 1: Write the failing test**

Use the helper tests from Task 1 to lock the fallback rules first.

**Step 2: Run test to verify it fails**

Run the same targeted test command if a new fallback case is added.

**Step 3: Write minimal implementation**

```swift
@EnvironmentObject private var locationHub: LocationHub
let distText = FriendJourneyDistancePresentation.makeDistanceText(
    currentLocation: locationHub.currentLocation,
    lastKnownLocation: locationHub.lastKnownLocation,
    journeyEndCoordinate: j.coordinates.last?.cl
)
```

**Step 4: Run test to verify it passes**

Re-run the targeted test command.

### Task 3: Split the overlay message into two timed speech bubbles

**Files:**
- Modify: `StreetStamps/FriendMapCharacterOverlay.swift`

**Step 1: Write the failing test**

Prefer behavior coverage from the helper tests and keep the overlay change minimal because this project currently does not have view-level snapshot coverage for this component.

**Step 2: Run test to verify it fails**

Not applicable without a UI test harness; rely on compilation plus the helper regression tests.

**Step 3: Write minimal implementation**

```swift
if showFriendBubble { SpeechBubble(text: "I am \(distanceText) away from you.") }
if showMyBubble { SpeechBubble(text: "But I am right next to you.") }
```

**Step 4: Run test to verify it passes**

Run:
`xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: BUILD SUCCEEDED
