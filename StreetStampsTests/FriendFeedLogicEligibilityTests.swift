import XCTest
@testable import StreetStamps

final class FriendFeedLogicEligibilityTests: XCTestCase {
    func test_shortJourney_withOnlyOverallMemoryText_isEligible() {
        let journey = makeJourney(
            distance: 500,
            memories: [],
            overallMemory: "great walk",
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_shortJourney_withOnlyOverallMemoryPhotos_isEligible() {
        let journey = makeJourney(
            distance: 500,
            memories: [],
            overallMemory: nil,
            overallMemoryImageURLs: ["https://example.com/a.jpg"]
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_shortJourney_withWhitespaceOnlyOverallMemoryAndNoPhotos_isNotEligible() {
        let journey = makeJourney(
            distance: 500,
            memories: [],
            overallMemory: "   \n  ",
            overallMemoryImageURLs: []
        )
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_shortJourney_withPerPointMemory_isEligible() {
        let journey = makeJourney(
            distance: 500,
            memories: [
                FriendSharedMemory(
                    id: "m1",
                    title: "t",
                    notes: "n",
                    timestamp: Date(),
                    imageURLs: []
                )
            ],
            overallMemory: nil,
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_longJourney_withNoMemory_isEligible() {
        let journey = makeJourney(
            distance: 3_000,
            memories: [],
            overallMemory: nil,
            overallMemoryImageURLs: []
        )
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_shortJourney_withNoMemory_isNotEligible() {
        let journey = makeJourney(
            distance: 500,
            memories: [],
            overallMemory: nil,
            overallMemoryImageURLs: []
        )
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(journey))
    }

    func test_privateJourney_withMemory_isNotEligible() {
        let journey = makeJourney(
            distance: 5_000,
            visibility: .private,
            memories: [],
            overallMemory: "anything",
            overallMemoryImageURLs: []
        )
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(journey))
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
