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

    func test_cardReaction_receivedReturnsReactionForDisplay() {
        let reaction = PostcardReaction(
            id: "pr_1",
            postcardMessageID: "pm_1",
            fromUserID: "me_1",
            viewedAt: Date(timeIntervalSince1970: 1_700_000_100),
            reactionEmoji: "❤️",
            comment: "So nice",
            reactedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let message = makeMessage(fromUserID: "friend_1", toUserID: "me_1", reaction: reaction)

        XCTAssertEqual(
            PostcardInboxPresentation.cardReaction(for: message, box: .received),
            reaction
        )
    }

    func test_draftStatusPresentation_sendingShowsQueuedConfirmationMessage() {
        let presentation = PostcardInboxPresentation.draftStatusPresentation(for: .sending) { key in
            switch key {
            case "postcard_sending_status":
                return "发送中"
            case "postcard_send_queued_detail":
                return "已加入发送队列，正在确认是否发送成功"
            default:
                return key
            }
        }

        XCTAssertEqual(presentation?.badgeText, "发送中")
        XCTAssertEqual(presentation?.detailText, "已加入发送队列，正在确认是否发送成功")
        XCTAssertEqual(presentation?.showsRetry, false)
    }

    func test_draftStatusPresentation_failedShowsRetryState() {
        let presentation = PostcardInboxPresentation.draftStatusPresentation(for: .failed) { key in
            switch key {
            case "postcard_failed_status":
                return "发送失败"
            case "postcard_failed_retry_detail":
                return "发送失败，可重试"
            default:
                return key
            }
        }

        XCTAssertEqual(presentation?.badgeText, "发送失败")
        XCTAssertEqual(presentation?.detailText, "发送失败，可重试")
        XCTAssertEqual(presentation?.showsRetry, true)
    }

    func test_draftStatusPresentation_sentShowsConfirmedState() {
        let presentation = PostcardInboxPresentation.draftStatusPresentation(for: .sent) { key in
            switch key {
            case "postcard_sent_status":
                return "已发送"
            default:
                return key
            }
        }

        XCTAssertEqual(presentation?.badgeText, "已发送")
        XCTAssertEqual(presentation?.detailText, "已发送")
        XCTAssertEqual(presentation?.showsRetry, false)
    }

    private func makeMessage(
        fromUserID: String,
        toUserID: String,
        reaction: PostcardReaction? = nil
    ) -> BackendPostcardMessageDTO {
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
            status: nil,
            reaction: reaction
        )
    }
}
