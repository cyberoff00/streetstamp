import XCTest
@testable import StreetStamps

final class FriendFeedLogicEligibilityTests: XCTestCase {
    // Eligibility now collapses to a pure visibility check. Distance / memory
    // requirements were removed in tandem with the publish-side gate so the
    // two sides cannot drift.

    func test_shortJourney_withNoMemory_isEligible_whenFriendsOnly() {
        let journey = makeJourney(
            distance: 100,
            memories: [],
            overallMemory: nil,
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_publicJourney_isEligible() {
        let journey = makeJourney(
            distance: 500,
            visibility: .public,
            memories: [],
            overallMemory: nil,
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_privateJourney_isNotEligible_evenWithMemory() {
        let journey = makeJourney(
            distance: 5_000,
            visibility: .private,
            memories: [],
            overallMemory: "anything",
            overallMemoryImageURLs: []
        )
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_hasMemoryContent_overallText_isCounted() {
        let journey = makeJourney(
            distance: 100,
            memories: [],
            overallMemory: "great walk",
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.hasMemoryContent(journey))
    }

    func test_hasMemoryContent_whitespaceText_isNotCounted() {
        let journey = makeJourney(
            distance: 100,
            memories: [],
            overallMemory: "   \n  ",
            overallMemoryImageURLs: []
        )
        XCTAssertFalse(FriendFeedLogic.hasMemoryContent(journey))
    }

    private func makeJourney(
        distance: Double,
        visibility: JourneyVisibility = .friendsOnly,
        memories: [FriendSharedMemory],
        overallMemory: String?,
        overallMemoryImageURLs: [String]
    ) -> FriendSharedJourney {
        FriendSharedJourney(
            id: "j1",
            title: "Title",
            cityID: "Tokyo|JP",
            activityTag: nil,
            overallMemory: overallMemory,
            overallMemoryImageURLs: overallMemoryImageURLs,
            distance: distance,
            startTime: Date().addingTimeInterval(-600),
            endTime: Date(),
            visibility: visibility,
            routeCoordinates: [],
            memories: memories
        )
    }
}
