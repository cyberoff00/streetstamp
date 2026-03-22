import XCTest
@testable import StreetStamps

final class FriendsFeedOrderingTests: XCTestCase {
    func test_sortJourneys_prefersNewestTimestampAndFallsBackToJourneyID() {
        let sharedAt = Date(timeIntervalSince1970: 1_000)
        let earlier = FriendSharedJourney(
            id: "journey_a",
            title: "A",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 900),
            endTime: Date(timeIntervalSince1970: 950),
            visibility: .friendsOnly,
            sharedAt: sharedAt,
            routeCoordinates: [],
            memories: []
        )
        let later = FriendSharedJourney(
            id: "journey_b",
            title: "B",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 900),
            endTime: Date(timeIntervalSince1970: 950),
            visibility: .friendsOnly,
            sharedAt: sharedAt,
            routeCoordinates: [],
            memories: []
        )

        let sorted = FriendsFeedOrdering.sortJourneys([later, earlier])

        XCTAssertEqual(sorted.map(\.id), ["journey_a", "journey_b"])
    }

    func test_sortEvents_prefersNewestTimestampAndFallsBackToEventID() {
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let eventB = FriendsFeedOrdering.EventIdentity(id: "feed_b", timestamp: timestamp)
        let eventA = FriendsFeedOrdering.EventIdentity(id: "feed_a", timestamp: timestamp)

        let sorted = FriendsFeedOrdering.sortEvents([eventB, eventA])

        XCTAssertEqual(sorted.map(\.id), ["feed_a", "feed_b"])
    }
}
