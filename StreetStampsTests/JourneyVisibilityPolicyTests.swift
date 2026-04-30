import XCTest
@testable import StreetStamps

final class JourneyVisibilityPolicyTests: XCTestCase {
    func test_guest_cannot_change_visibility() {
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: .private,
            target: .friendsOnly,
            isLoggedIn: false,
            journeyDistance: 5_000,
            hasMemory: false
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
            hasMemory: false
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
            hasMemory: false
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
            hasMemory: true
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.reason)
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
