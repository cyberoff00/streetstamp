import XCTest
@testable import StreetStamps

final class JourneyLikesPresentationTests: XCTestCase {
    func test_memoryMainViewLoadsOnlyBeforeStoreHasLoaded() {
        XCTAssertTrue(JourneyMemoryMainLoadPolicy.shouldLoadOnAppear(hasLoaded: false))
        XCTAssertFalse(JourneyMemoryMainLoadPolicy.shouldLoadOnAppear(hasLoaded: true))
    }

    func test_likersFromNotifications_deduplicatesByUserAndFiltersJourney() {
        let now = Date()
        let later = now.addingTimeInterval(60)
        let notifications = [
            BackendNotificationItem(
                id: "n-1",
                type: "journey_like",
                fromUserID: "user-1",
                fromDisplayName: "Alice",
                journeyID: "journey-1",
                journeyTitle: nil,
                message: "Alice liked it",
                createdAt: now,
                read: false,
                postcardMessageID: nil,
                cityID: nil,
                cityName: nil,
                photoURL: nil,
                messageText: nil
            ),
            BackendNotificationItem(
                id: "n-2",
                type: "journey_like",
                fromUserID: "user-1",
                fromDisplayName: "Alice",
                journeyID: "journey-1",
                journeyTitle: nil,
                message: "Alice liked it again",
                createdAt: later,
                read: true,
                postcardMessageID: nil,
                cityID: nil,
                cityName: nil,
                photoURL: nil,
                messageText: nil
            ),
            BackendNotificationItem(
                id: "n-3",
                type: "journey_like",
                fromUserID: "user-2",
                fromDisplayName: "Bob",
                journeyID: "journey-2",
                journeyTitle: nil,
                message: "Bob liked another journey",
                createdAt: later,
                read: false,
                postcardMessageID: nil,
                cityID: nil,
                cityName: nil,
                photoURL: nil,
                messageText: nil
            )
        ]

        let likers = JourneyLikesPresentation.likers(from: notifications, journeyID: "journey-1")

        XCTAssertEqual(likers.map(\.id), ["user-1"])
        XCTAssertEqual(likers.first?.name, "Alice")
        XCTAssertEqual(likers.first?.likedAt, later)
    }
}
