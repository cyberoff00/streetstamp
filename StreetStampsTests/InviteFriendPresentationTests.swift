import XCTest
@testable import StreetStamps

final class InviteFriendPresentationTests: XCTestCase {
    func test_titleUsesUppercasedDisplayName() {
        let presentation = InviteFriendPresentation(
            displayName: "Claire",
            exclusiveID: "claire",
            inviteCode: "ABCD1234"
        )

        XCTAssertEqual(presentation.titleText, "CLAIRE")
    }

    func test_codeTextKeepsInviteCodeVisible() {
        let presentation = InviteFriendPresentation(
            displayName: "Claire",
            exclusiveID: "claire",
            inviteCode: "ABCD1234"
        )

        XCTAssertEqual(presentation.codeText, "ABCD1234")
    }

    func test_visibleExclusiveIDText_isHiddenEvenWhenExclusiveIDExists() {
        let presentation = InviteFriendPresentation(
            displayName: "Claire",
            exclusiveID: "claire",
            inviteCode: "ABCD1234"
        )

        XCTAssertNil(presentation.visibleExclusiveIDText)
    }
}
