import XCTest
@testable import StreetStamps

final class JourneyDetailSheetRoutePresentationTests: XCTestCase {
    func test_primaryRoute_prefersLikesWhenJourneyAlreadyHasLikes() {
        XCTAssertEqual(
            JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount: 3),
            .likes
        )
    }

    func test_primaryRoute_fallsBackToVisibilityWhenJourneyHasNoLikes() {
        XCTAssertEqual(
            JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount: 0),
            .visibility
        )
    }
}
