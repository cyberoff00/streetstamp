import XCTest
@testable import StreetStamps

final class FirstProfileSetupPresentationTests: XCTestCase {
    func test_releasePresentationRequiresPendingSetup() {
        XCTAssertTrue(
            FirstProfileSetupPresentation.shouldPresent(requiresProfileSetup: true)
        )
        XCTAssertFalse(
            FirstProfileSetupPresentation.shouldPresent(requiresProfileSetup: false)
        )
    }
}
