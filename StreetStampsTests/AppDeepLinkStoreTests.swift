import XCTest
@testable import StreetStamps

final class AppDeepLinkStoreTests: XCTestCase {
    @MainActor
    func testHandleIncomingURLStoresPendingPasswordResetToken() {
        let store = AppDeepLinkStore()

        let handled = store.handleIncomingURL(URL(string: "streetstamps://reset-password?token=abc123")!)

        XCTAssertTrue(handled)
        XCTAssertEqual(store.pendingPasswordResetToken, "abc123")
    }

    @MainActor
    func testHandleIncomingURLIgnoresPasswordResetWithoutToken() {
        let store = AppDeepLinkStore()

        let handled = store.handleIncomingURL(URL(string: "streetstamps://reset-password?token=")!)

        XCTAssertFalse(handled)
        XCTAssertNil(store.pendingPasswordResetToken)
    }
}
