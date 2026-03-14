import XCTest
import CoreLocation
@testable import StreetStamps

@MainActor
final class TrackingServiceResumeLocationTests: XCTestCase {
    override func tearDown() {
        TrackingService.shared.stopJourney()
        TrackingService.shared.userLocation = nil
        super.tearDown()
    }

    func test_resumeJourney_clearsStaleUserLocation() {
        let service = TrackingService.shared
        service.userLocation = CLLocation(latitude: 51.5074, longitude: -0.1278)

        service.resumeJourney()

        XCTAssertNil(service.userLocation)
    }

    func test_resumeFromPause_clearsStaleUserLocation() {
        let service = TrackingService.shared
        service.resumeJourney()
        service.userLocation = CLLocation(latitude: 48.8566, longitude: 2.3522)
        service.pauseJourney()

        service.resumeFromPause()

        XCTAssertNil(service.userLocation)
    }
}
