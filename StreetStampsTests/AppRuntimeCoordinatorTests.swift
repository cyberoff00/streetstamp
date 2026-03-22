import XCTest
@testable import StreetStamps

final class AppRuntimeCoordinatorTests: XCTestCase {
    func test_consumeInitialAuthEntryPresentation_returnsTrueOnlyOnce() {
        let suiteName = "AppRuntimeCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertTrue(
            AppAuthPresentationCoordinator.consumeInitialAuthEntryPresentation(
                hasSeenIntroSlides: true,
                isLoggedIn: false,
                defaults: defaults
            )
        )

        XCTAssertFalse(
            AppAuthPresentationCoordinator.consumeInitialAuthEntryPresentation(
                hasSeenIntroSlides: true,
                isLoggedIn: false,
                defaults: defaults
            )
        )
    }

    func test_consumeInitialAuthEntryPresentation_respectsIntroAndLoginState() {
        let suiteName = "AppRuntimeCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertFalse(
            AppAuthPresentationCoordinator.consumeInitialAuthEntryPresentation(
                hasSeenIntroSlides: false,
                isLoggedIn: false,
                defaults: defaults
            )
        )

        XCTAssertFalse(
            AppAuthPresentationCoordinator.consumeInitialAuthEntryPresentation(
                hasSeenIntroSlides: true,
                isLoggedIn: true,
                defaults: defaults
            )
        )
    }
}
