import XCTest
@testable import StreetStamps

final class CityDeepMemoryVisibilityTests: XCTestCase {
    func test_shouldShowPins_whenZoomedInBelowThreshold() {
        XCTAssertTrue(CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: 0.02))
    }

    func test_shouldHidePins_whenAtOrAboveThreshold() {
        XCTAssertFalse(CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: 0.03))
        XCTAssertFalse(CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: 0.08))
    }

    func test_alphas_switchExclusivelyBetweenPinsAndDots() {
        XCTAssertEqual(CityDeepMemoryVisibility.pinAlpha(shouldShowPins: true), 1.0)
        XCTAssertEqual(CityDeepMemoryVisibility.dotAlpha(shouldShowPins: true), 0.0)
        XCTAssertEqual(CityDeepMemoryVisibility.pinAlpha(shouldShowPins: false), 0.0)
        XCTAssertEqual(CityDeepMemoryVisibility.dotAlpha(shouldShowPins: false), 1.0)
    }
}
