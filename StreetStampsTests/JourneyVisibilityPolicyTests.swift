import XCTest
@testable import StreetStamps

final class JourneyVisibilityPolicyTests: XCTestCase {
    func test_guest_cannot_change_visibility() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: false
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .loginRequired)
    }

    func test_logged_in_user_can_publish_short_journey_without_memory() {
        // Distance/memory gate was removed: any logged-in user can promote a
        // journey to friends-only regardless of length or content. Quota is
        // enforced at the call site via PublicJourneyQuota, not here.
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: true
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.reason)
    }

    func test_no_op_visibility_change_is_always_allowed() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .private,
            isLoggedIn: false
        )
        XCTAssertTrue(decision.isAllowed)
    }

    func test_returning_to_private_does_not_require_login() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .friendsOnly,
            target: .private,
            isLoggedIn: false
        )
        XCTAssertTrue(decision.isAllowed)
    }

    func test_overall_memory_text_counts_as_memory_content() {
        var journey = JourneyRoute()
        journey.overallMemory = "今天去了一个很美的地方"
        XCTAssertTrue(journey.hasMemoryContent)
    }

    func test_overall_memory_photo_counts_as_memory_content() {
        var journey = JourneyRoute()
        journey.overallMemoryImagePaths = ["photo1.jpg"]
        XCTAssertTrue(journey.hasMemoryContent)
    }

    func test_overall_memory_remote_url_counts_as_memory_content() {
        var journey = JourneyRoute()
        journey.overallMemoryRemoteImageURLs = ["https://example.com/p.jpg"]
        XCTAssertTrue(journey.hasMemoryContent)
    }

    func test_blank_overall_memory_does_not_count() {
        var journey = JourneyRoute()
        journey.overallMemory = "   \n  "
        XCTAssertFalse(journey.hasMemoryContent)
    }

    func test_visibility_sheet_option_presentations_expose_private_then_friends_cards() {
        let options = JourneyVisibilitySheetPresentation.optionPresentations

        XCTAssertEqual(options.map(\.visibility), [.private, .friendsOnly])
        XCTAssertEqual(options.map(\.symbolName), ["lock.fill", "person.2.fill"])
        XCTAssertEqual(options.map(\.accentStyle), [.neutral, .accent])
    }
}
