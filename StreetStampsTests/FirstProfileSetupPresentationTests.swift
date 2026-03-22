import XCTest
@testable import StreetStamps

final class FirstProfileSetupPresentationTests: XCTestCase {
    func test_releasePresentationRequiresPendingSetup() {
        XCTAssertTrue(
            FirstProfileSetupPresentation.shouldPresent(
                requiresProfileSetup: true,
                debugOverrideEnabled: false
            )
        )
        XCTAssertFalse(
            FirstProfileSetupPresentation.shouldPresent(
                requiresProfileSetup: false,
                debugOverrideEnabled: false
            )
        )
    }

    func test_debugOverrideForcesPresentationWithoutPendingSetup() {
        XCTAssertTrue(
            FirstProfileSetupPresentation.shouldPresent(
                requiresProfileSetup: false,
                debugOverrideEnabled: true
            )
        )
    }
}
