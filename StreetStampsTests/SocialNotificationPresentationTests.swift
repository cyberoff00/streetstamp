import XCTest
@testable import StreetStamps

final class SocialNotificationPresentationTests: XCTestCase {
    func test_badgeTitle_usesPreciseTypeSpecificCopy() {
        let friendRequest = BackendNotificationItem(
            id: "n3",
            type: "friend_request",
            fromUserID: "u3",
            fromDisplayName: "Lina",
            journeyID: nil,
            journeyTitle: nil,
            message: "Lina sent you a friend request",
            createdAt: .distantPast,
            read: false,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )
        let accepted = BackendNotificationItem(
            id: "n4",
            type: "friend_request_accepted",
            fromUserID: "u4",
            fromDisplayName: "Noah",
            journeyID: nil,
            journeyTitle: nil,
            message: "Noah accepted your friend request",
            createdAt: .distantPast,
            read: false,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )

        XCTAssertEqual(
            SocialNotificationPresentation.badgeTitle(for: friendRequest, locale: Locale(identifier: "en")),
            "Friend Request"
        )
        XCTAssertEqual(
            SocialNotificationPresentation.badgeTitle(for: accepted, locale: Locale(identifier: "en")),
            "Friend Update"
        )
        XCTAssertEqual(
            SocialNotificationPresentation.badgeTitle(for: friendRequest, locale: Locale(identifier: "zh-Hans")),
            "好友申请"
        )
        XCTAssertEqual(
            SocialNotificationPresentation.badgeTitle(for: accepted, locale: Locale(identifier: "zh-Hans")),
            "好友动态"
        )
    }

    func test_journeyLikeMessageUsesLocalizedFormat() {
        let item = BackendNotificationItem(
            id: "n1",
            type: "journey_like",
            fromUserID: "u1",
            fromDisplayName: "Alex",
            journeyID: "j1",
            journeyTitle: "Night Walk",
            message: "Alex liked your journey \"Night Walk\"",
            createdAt: .distantPast,
            read: false,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )

        XCTAssertEqual(
            SocialNotificationPresentation.message(for: item, locale: Locale(identifier: "en")),
            "Alex liked your journey \"Night Walk\""
        )
        XCTAssertEqual(
            SocialNotificationPresentation.message(for: item, locale: Locale(identifier: "zh-Hans")),
            "Alex 赞了你的旅程「Night Walk」"
        )
    }

    func test_profileStompMessageUsesLocalizedFormat() {
        let item = BackendNotificationItem(
            id: "n2",
            type: "profile_stomp",
            fromUserID: "u2",
            fromDisplayName: "Mika",
            journeyID: nil,
            journeyTitle: nil,
            message: "Mika在你的沙发上坐了一坐",
            createdAt: .distantPast,
            read: false,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )

        XCTAssertEqual(
            SocialNotificationPresentation.message(for: item, locale: Locale(identifier: "en")),
            "Mika sat on your sofa"
        )
        XCTAssertEqual(
            SocialNotificationPresentation.message(for: item, locale: Locale(identifier: "zh-Hans")),
            "Mika在你的沙发上坐了一坐"
        )
    }
}
