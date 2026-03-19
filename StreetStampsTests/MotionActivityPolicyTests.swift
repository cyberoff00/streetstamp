import XCTest
import CoreLocation
@testable import StreetStamps

final class MotionActivityPolicyTests: XCTestCase {
    func test_runsWhenJourneyTrackingIsActive() {
        XCTAssertTrue(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: true,
                isPassiveLifelogActive: false
            )
        )
    }

    func test_runsWhenPassiveLifelogIsEnabled() {
        XCTAssertTrue(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: false,
                isPassiveLifelogActive: true
            )
        )
    }

    func test_stopsWhenJourneyAndPassiveLifelogAreInactive() {
        XCTAssertFalse(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: false,
                isPassiveLifelogActive: false
            )
        )
    }

    func test_passiveLifelogRequiresAlwaysAuthorization() {
        XCTAssertFalse(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: false,
                isPassiveLifelogEnabled: true,
                authorizationStatus: .authorizedWhenInUse
            )
        )
    }

    func test_passiveLifelogRunsWithAlwaysAuthorization() {
        XCTAssertTrue(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: false,
                isPassiveLifelogEnabled: true,
                authorizationStatus: .authorizedAlways
            )
        )
    }
}
