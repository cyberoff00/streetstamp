import XCTest
import CoreLocation
@testable import StreetStamps

final class FriendJourneyDistancePresentationTests: XCTestCase {
    func test_makeDistanceText_usesStraightLineDistanceToJourneyEndpoint() {
        let currentLocation = CLLocation(latitude: 0, longitude: 0)
        let journeyEndCoordinate = CLLocationCoordinate2D(latitude: 0.01, longitude: 0)

        let text = FriendJourneyDistancePresentation.makeDistanceText(
            currentLocation: currentLocation,
            lastKnownLocation: nil,
            journeyEndCoordinate: journeyEndCoordinate
        )

        XCTAssertEqual(text, "1.1 km")
    }

    func test_makeDistanceText_fallsBackToLastKnownLocationWhenLiveLocationIsMissing() {
        let lastKnownLocation = CLLocation(latitude: 0, longitude: 0)
        let journeyEndCoordinate = CLLocationCoordinate2D(latitude: 0.001, longitude: 0)

        let text = FriendJourneyDistancePresentation.makeDistanceText(
            currentLocation: nil,
            lastKnownLocation: lastKnownLocation,
            journeyEndCoordinate: journeyEndCoordinate
        )

        XCTAssertEqual(text, "111 m")
    }

    func test_makeDistanceText_returnsUnknownWhenDistanceInputsAreMissing() {
        let text = FriendJourneyDistancePresentation.makeDistanceText(
            currentLocation: nil,
            lastKnownLocation: nil,
            journeyEndCoordinate: nil
        )

        XCTAssertEqual(text, "unknown")
    }
}
