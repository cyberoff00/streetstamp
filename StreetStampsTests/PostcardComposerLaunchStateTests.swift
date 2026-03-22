import XCTest
@testable import StreetStamps

final class PostcardComposerLaunchStateTests: XCTestCase {
    func test_initialRecipient_isNilForHeaderEntryWithoutPrefilledFriend() {
        let recipient = PostcardComposerPresentation.initialRecipient(
            prefilledFriendID: nil,
            prefilledFriendName: nil
        )

        XCTAssertNil(recipient)
    }

    func test_initialRecipient_usesPrefilledFriendForFriendProfileEntry() {
        let recipient = PostcardComposerPresentation.initialRecipient(
            prefilledFriendID: "friend_1",
            prefilledFriendName: "Mika"
        )

        XCTAssertEqual(
            recipient,
            PostcardRecipient(userID: "friend_1", displayName: "Mika")
        )
    }

    func test_canPreview_isFalseUntilRecipientIsSelected() {
        let canPreview = PostcardComposerPresentation.canPreview(
            recipient: nil,
            selectedCityID: "city_1",
            localImagePath: "/tmp/postcard.jpg",
            messageText: "Hello from London"
        )

        XCTAssertFalse(canPreview)
    }

    func test_canPreview_isTrueWhenRecipientAndRequiredFieldsExist() {
        let canPreview = PostcardComposerPresentation.canPreview(
            recipient: PostcardRecipient(userID: "friend_1", displayName: "Mika"),
            selectedCityID: "city_1",
            localImagePath: "/tmp/postcard.jpg",
            messageText: "Hello from London"
        )

        XCTAssertTrue(canPreview)
    }
}
