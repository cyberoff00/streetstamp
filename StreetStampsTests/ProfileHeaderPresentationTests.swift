import XCTest
@testable import StreetStamps

final class ProfileHeaderPresentationTests: XCTestCase {
    func test_cloud_is_hidden_without_notifications() {
        XCTAssertFalse(ProfileHeaderPresentation.showsNotificationCloud(notificationCount: 0))
    }

    func test_cloud_is_visible_with_notifications() {
        XCTAssertTrue(ProfileHeaderPresentation.showsNotificationCloud(notificationCount: 1))
        XCTAssertTrue(ProfileHeaderPresentation.showsNotificationCloud(notificationCount: 8))
    }

    func test_level_help_message_uses_remaining_journeys() {
        XCTAssertEqual(
            ProfileHeaderPresentation.levelHelpText(remainingJourneys: 3),
            "还差 3 段旅程升级"
        )
    }

    func test_social_notification_policy_includes_friend_request_events() {
        XCTAssertTrue(SocialNotificationPolicy.supports(type: "friend_request"))
        XCTAssertTrue(SocialNotificationPolicy.supports(type: "friend_request_accepted"))
    }
}
