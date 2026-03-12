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
}
