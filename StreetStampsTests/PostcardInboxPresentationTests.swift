import XCTest
@testable import StreetStamps

final class PostcardInboxPresentationTests: XCTestCase {
    func test_recipientLabelPrefersDisplayNameForDrafts() {
        XCTAssertEqual(
            PostcardInboxPresentation.recipientLabel(toDisplayName: "Mika Horizon", toUserID: "user_123"),
            "Mika Horizon"
        )
    }

    func test_recipientLabelFallsBackToUserIDWhenDisplayNameMissing() {
        XCTAssertEqual(
            PostcardInboxPresentation.recipientLabel(toDisplayName: "   ", toUserID: "user_123"),
            "user_123"
        )
    }
}
