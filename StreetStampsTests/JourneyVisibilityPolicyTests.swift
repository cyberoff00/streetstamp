import XCTest
@testable import StreetStamps

final class JourneyVisibilityPolicyTests: XCTestCase {
    func test_guest_cannot_change_visibility() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: false,
            journeyDistance: 5_000,
            memoryCount: 0
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .loginRequired)
    }

    func test_logged_in_user_needs_distance_or_memory_for_friends_visibility() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: true,
            journeyDistance: 1_999,
            memoryCount: 0
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .journeyNotEligible)
    }

    func test_logged_in_user_can_change_visibility_when_journey_is_long_enough() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: true,
            journeyDistance: 2_000,
            memoryCount: 0
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.reason)
    }

    func test_logged_in_user_can_change_visibility_when_journey_has_memory() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: true,
            journeyDistance: 100,
            memoryCount: 1
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.reason)
    }
}
