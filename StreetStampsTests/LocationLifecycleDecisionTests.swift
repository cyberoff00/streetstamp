import XCTest
@testable import StreetStamps

final class LocationLifecycleDecisionTests: XCTestCase {
    func test_idleLaunch_requestsSingleRefreshWhenJourneyAndPassiveAreOff() {
        let action = LocationLifecycleDecision.idleActivationAction(
            isTrackingJourney: false,
            isPassiveEnabled: false,
            authorizationStatus: .authorizedWhenInUse
        )

        XCTAssertEqual(action, .requestSingleRefresh)
    }

    func test_idleLaunch_startsPassiveOnlyWhenEnabledAndAlwaysAuthorized() {
        let action = LocationLifecycleDecision.idleActivationAction(
            isTrackingJourney: false,
            isPassiveEnabled: true,
            authorizationStatus: .authorizedAlways
        )

        XCTAssertEqual(action, .startPassive)
    }

    func test_idleLaunch_doesNotStartPassiveWithoutAlwaysAuthorization() {
        let action = LocationLifecycleDecision.idleActivationAction(
            isTrackingJourney: false,
            isPassiveEnabled: true,
            authorizationStatus: .authorizedWhenInUse
        )

        XCTAssertEqual(action, .requestSingleRefresh)
    }

    func test_postJourney_returnsIdleWhenPassiveIsDisabled() {
        let action = LocationLifecycleDecision.postJourneyAction(
            isPassiveEnabled: false,
            authorizationStatus: .authorizedAlways
        )

        XCTAssertEqual(action, .stayIdle)
    }

    func test_postJourney_restartsPassiveWhenEligible() {
        let action = LocationLifecycleDecision.postJourneyAction(
            isPassiveEnabled: true,
            authorizationStatus: .authorizedAlways
        )

        XCTAssertEqual(action, .startPassive)
    }
}
