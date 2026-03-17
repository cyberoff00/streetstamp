import XCTest
@testable import StreetStamps

final class FriendsFeedUpdatePromptPolicyTests: XCTestCase {
    func test_doesNotPromptWhenCandidateFeedHasNoUnseenEventIDs() {
        XCTAssertFalse(
            FriendsFeedUpdatePromptPolicy.hasUnseenEvents(
                currentEventIDs: ["feed_a", "feed_b"],
                candidateEventIDs: ["feed_b", "feed_a"]
            )
        )
    }

    func test_promptsWhenCandidateFeedIntroducesNewEventID() {
        XCTAssertTrue(
            FriendsFeedUpdatePromptPolicy.hasUnseenEvents(
                currentEventIDs: ["feed_a", "feed_b"],
                candidateEventIDs: ["feed_c", "feed_b", "feed_a"]
            )
        )
    }
}
