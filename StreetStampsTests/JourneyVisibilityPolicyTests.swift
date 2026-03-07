import XCTest
@testable import StreetStamps

final class JourneyVisibilityPolicyTests: XCTestCase {
    func test_guest_cannot_change_visibility() {
        XCTAssertFalse(
            JourneyVisibilityPolicy.canEditVisibility(
                current: .private,
                target: .friendsOnly,
                isLoggedIn: false
            )
        )
        XCTAssertFalse(
            JourneyVisibilityPolicy.canEditVisibility(
                current: .friendsOnly,
                target: .private,
                isLoggedIn: false
            )
        )
    }

    func test_logged_in_user_can_change_visibility() {
        XCTAssertTrue(
            JourneyVisibilityPolicy.canEditVisibility(
                current: .private,
                target: .friendsOnly,
                isLoggedIn: true
            )
        )
    }
}
