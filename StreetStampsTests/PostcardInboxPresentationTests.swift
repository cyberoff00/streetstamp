import XCTest
@testable import StreetStamps

final class PostcardInboxPresentationTests: XCTestCase {
    func test_recipientLabelPrefersDisplayNameForDrafts() {
        XCTAssertEqual(
            PostcardInboxPresentation.recipientLabel(toDisplayName: "Mika Horizon", toUserID: "user_123"),
            "Mika Horizon"
        )
    }

    func test_recipientLabelFallsBackToFriendSnapshotNameBeforeUserID() {
        XCTAssertEqual(
            PostcardInboxPresentation.recipientLabel(
                toDisplayName: "   ",
                toUserID: "u_internal_friend_123",
                fallbackDisplayName: "Ariel Sun"
            ),
            "Ariel Sun"
        )
    }

    func test_recipientLabelHidesInternalUserIDWhenDisplayNameMissing() {
        XCTAssertEqual(
            PostcardInboxPresentation.recipientLabel(
                toDisplayName: "   ",
                toUserID: "u_e872904bd056bc8ff430e619",
                localize: { key in key == "unknown" ? "Unknown" : key }
            ),
            "Unknown"
        )
    }

    func test_senderLabelKeepsHumanReadableIdentifierWhenNoDisplayNameExists() {
        XCTAssertEqual(
            PostcardInboxPresentation.senderLabel(
                fromDisplayName: nil,
                fromUserID: "mika_horizon"
            ),
            "mika_horizon"
        )
    }

    func test_viewIdentityChangesWhenInitialBoxChanges() {
        XCTAssertNotEqual(
            PostcardInboxPresentation.viewIdentity(initialBox: .sent, focusMessageID: nil),
            PostcardInboxPresentation.viewIdentity(initialBox: .received, focusMessageID: nil)
        )
    }

    func test_viewIdentityIncludesFocusedMessage() {
        XCTAssertNotEqual(
            PostcardInboxPresentation.viewIdentity(initialBox: .received, focusMessageID: "pm_1"),
            PostcardInboxPresentation.viewIdentity(initialBox: .received, focusMessageID: "pm_2")
        )
    }

    func test_avatarLoadout_receivedPrefersSenderFriendLoadout() {
        let myLoadout = RobotLoadout(hairId: "hair_0001")
        let senderLoadout = RobotLoadout(hairId: "hair_0007")
        let message = makeMessage(fromUserID: "friend_1", toUserID: "me_1")

        let resolved = PostcardInboxPresentation.avatarLoadout(
            for: message,
            box: .received,
            myUserID: "me_1",
            myLoadout: myLoadout,
            friendLoadoutsByUserID: ["friend_1": senderLoadout]
        )

        XCTAssertEqual(resolved, senderLoadout.normalizedForCurrentAvatar())
    }

    func test_avatarLoadout_receivedFallsBackToDefaultWhenSenderLoadoutUnknown() {
        let myLoadout = RobotLoadout(hairId: "hair_0007")
        let message = makeMessage(fromUserID: "friend_404", toUserID: "me_1")

        let resolved = PostcardInboxPresentation.avatarLoadout(
            for: message,
            box: .received,
            myUserID: "me_1",
            myLoadout: myLoadout,
            friendLoadoutsByUserID: [:]
        )

        XCTAssertEqual(resolved, RobotLoadout.defaultBoy.normalizedForCurrentAvatar())
    }

    func test_avatarLoadout_sentUsesMyLoadout() {
        let myLoadout = RobotLoadout(hairId: "hair_0007")
        let senderLoadout = RobotLoadout(hairId: "hair_0001")
        let message = makeMessage(fromUserID: "me_1", toUserID: "friend_1")

        let resolved = PostcardInboxPresentation.avatarLoadout(
            for: message,
            box: .sent,
            myUserID: "me_1",
            myLoadout: myLoadout,
            friendLoadoutsByUserID: ["friend_1": senderLoadout]
        )

        XCTAssertEqual(resolved, myLoadout.normalizedForCurrentAvatar())
    }

    private func makeMessage(fromUserID: String, toUserID: String) -> BackendPostcardMessageDTO {
        BackendPostcardMessageDTO(
            messageID: "pm_1",
            type: "postcard",
            fromUserID: fromUserID,
            fromDisplayName: "From",
            toUserID: toUserID,
            toDisplayName: "To",
            cityID: "paris",
            cityName: "Paris",
            photoURL: nil,
            messageText: "hello",
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            clientDraftID: "draft_1",
            status: nil
        )
    }
}
