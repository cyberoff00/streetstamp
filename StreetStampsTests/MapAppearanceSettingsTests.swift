import XCTest
@testable import StreetStamps

final class MapAppearanceSettingsTests: XCTestCase {
    func test_usesMutedStandardMap_darkIsTrue_lightIsFalse() {
        XCTAssertTrue(MapAppearanceSettings.usesMutedStandardMap(for: .dark))
        XCTAssertFalse(MapAppearanceSettings.usesMutedStandardMap(for: .light))
    }
}

final class FriendFeedLogicTests: XCTestCase {
    func test_isJourneyEligible_requiresVisibilityAndDistanceOrMemory() {
        let base = makeJourney(visibility: .public, distance: 1_999, memories: [])
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(base))

        let withMemory = makeJourney(visibility: .friendsOnly, distance: 100, memories: [makeMemory()])
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(withMemory))

        let longDistance = makeJourney(visibility: .public, distance: 2_000, memories: [])
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(longDistance))

        let privateLongDistance = makeJourney(visibility: .private, distance: 10_000, memories: [makeMemory()])
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(privateLongDistance))
    }

    func test_eventTitle_forJourney_doesNotEmbedCityOrJourneyName() {
        let title = FriendFeedLogic.eventTitle(
            kind: .journey,
            cityName: "London",
            memoryCount: 0,
            journeyTitle: "London",
            localize: { key in
                if key == "friends_event_completed_journey" { return "完成了一段旅程" }
                return key
            }
        )

        XCTAssertEqual(title, "完成了一段旅程")
        XCTAssertFalse(title.contains("London"))
    }

    private func makeJourney(
        visibility: JourneyVisibility,
        distance: Double,
        memories: [FriendSharedMemory]
    ) -> FriendSharedJourney {
        FriendSharedJourney(
            id: UUID().uuidString,
            title: "London",
            activityTag: nil,
            overallMemory: nil,
            distance: distance,
            startTime: Date(),
            endTime: Date(),
            visibility: visibility,
            routeCoordinates: [],
            memories: memories
        )
    }

    private func makeMemory() -> FriendSharedMemory {
        FriendSharedMemory(
            id: UUID().uuidString,
            title: "m",
            notes: "",
            timestamp: Date(),
            imageURLs: []
        )
    }
}
