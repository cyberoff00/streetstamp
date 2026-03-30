import XCTest
@testable import StreetStamps

final class MapNavigationPresentationPolicyTests: XCTestCase {
    func test_cityDeepView_prefersModalPresentation() {
        XCTAssertEqual(
            MapNavigationPresentationPolicy.presentation(for: .cityDeepView),
            .modal
        )
    }

    func test_journeyMemoryDetail_prefersModalPresentation() {
        XCTAssertEqual(
            MapNavigationPresentationPolicy.presentation(for: .journeyMemoryDetail),
            .modal
        )
    }

    func test_friendJourneyDetail_prefersModalPresentation() {
        XCTAssertEqual(
            MapNavigationPresentationPolicy.presentation(for: .friendJourneyDetail),
            .modal
        )
    }

    func test_regularProfileFlow_prefersPushPresentation() {
        XCTAssertEqual(
            MapNavigationPresentationPolicy.presentation(for: .standardDetail),
            .push
        )
    }
}
