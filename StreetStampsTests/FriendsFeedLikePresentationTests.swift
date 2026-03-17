import XCTest
@testable import StreetStamps

final class FriendsFeedLikePresentationTests: XCTestCase {
    func test_statsPairs_includeCurrentUserJourneyEvents() {
        let pairs = FriendsFeedLikePresentation.statsPairs(
            from: [
                (friendID: "me", journeyID: "journey-1"),
                (friendID: "friend-1", journeyID: "journey-2"),
                (friendID: "friend-2", journeyID: nil)
            ]
        )

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].friendID, "me")
        XCTAssertEqual(pairs[0].journeyID, "journey-1")
        XCTAssertEqual(pairs[1].friendID, "friend-1")
        XCTAssertEqual(pairs[1].journeyID, "journey-2")
    }

    func test_actionMode_usesLikersForCurrentUserJourney() {
        XCTAssertEqual(
            FriendsFeedLikePresentation.actionMode(currentUserID: "me", eventFriendID: "me", hasJourney: true),
            .showLikers
        )
        XCTAssertEqual(
            FriendsFeedLikePresentation.actionMode(currentUserID: "me", eventFriendID: "friend-1", hasJourney: true),
            .toggleLike
        )
        XCTAssertNil(
            FriendsFeedLikePresentation.actionMode(currentUserID: "me", eventFriendID: "friend-1", hasJourney: false)
        )
    }
}
