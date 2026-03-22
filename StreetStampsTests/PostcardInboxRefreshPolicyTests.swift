import XCTest
@testable import StreetStamps

final class PostcardInboxRefreshPolicyTests: XCTestCase {
    func test_hasUnseenItems_returnsFalseWhenBothBoxesContainSameMessages() {
        XCTAssertFalse(
            PostcardInboxRefreshPolicy.hasUnseenItems(
                currentSentMessageIDs: ["sent_1"],
                candidateSentMessageIDs: ["sent_1"],
                currentReceivedMessageIDs: ["received_1", "received_2"],
                candidateReceivedMessageIDs: ["received_2", "received_1"]
            )
        )
    }

    func test_hasUnseenItems_returnsTrueWhenReceivedBoxAddsMessage() {
        XCTAssertTrue(
            PostcardInboxRefreshPolicy.hasUnseenItems(
                currentSentMessageIDs: ["sent_1"],
                candidateSentMessageIDs: ["sent_1"],
                currentReceivedMessageIDs: ["received_1"],
                candidateReceivedMessageIDs: ["received_2", "received_1"]
            )
        )
    }

    func test_hasUnseenItems_returnsTrueWhenSentBoxAddsMessage() {
        XCTAssertTrue(
            PostcardInboxRefreshPolicy.hasUnseenItems(
                currentSentMessageIDs: ["sent_1"],
                candidateSentMessageIDs: ["sent_2", "sent_1"],
                currentReceivedMessageIDs: ["received_1"],
                candidateReceivedMessageIDs: ["received_1"]
            )
        )
    }
}
