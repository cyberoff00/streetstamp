import XCTest
@testable import StreetStamps

final class FriendsFeedNavigationPolicyTests: XCTestCase {
    func test_selfFeedAvatarOpensCurrentUserProfile() {
        XCTAssertTrue(
            FriendsFeedNavigationPolicy.opensCurrentUserProfile(
                currentUserID: "me",
                targetFriendID: "me"
            )
        )
        XCTAssertFalse(
            FriendsFeedNavigationPolicy.opensCurrentUserProfile(
                currentUserID: "me",
                targetFriendID: "friend-1"
            )
        )
    }

    func test_selfFeedJourneyOpensCurrentUserJourneyDetail() {
        XCTAssertTrue(
            FriendsFeedNavigationPolicy.opensCurrentUserJourneyDetail(
                currentUserID: "me",
                targetFriendID: "me"
            )
        )
        XCTAssertFalse(
            FriendsFeedNavigationPolicy.opensCurrentUserJourneyDetail(
                currentUserID: "me",
                targetFriendID: "friend-1"
            )
        )
    }
}
