import XCTest
@testable import StreetStamps

final class PostcardSidebarVisibilityPolicyTests: XCTestCase {
    func test_composerAndPreviewScopes_hideGlobalSidebarButton() {
        XCTAssertTrue(PostcardSidebarVisibilityScope.composer.hidesGlobalSidebarButton)
        XCTAssertTrue(PostcardSidebarVisibilityScope.preview.hidesGlobalSidebarButton)
    }

    func test_composerAndPreviewScopes_useDistinctTokens() {
        XCTAssertNotEqual(PostcardSidebarVisibilityScope.composer.token, PostcardSidebarVisibilityScope.preview.token)
        XCTAssertFalse(PostcardSidebarVisibilityScope.composer.token.isEmpty)
        XCTAssertFalse(PostcardSidebarVisibilityScope.preview.token.isEmpty)
    }
}
