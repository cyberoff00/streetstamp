import XCTest
@testable import StreetStamps

final class FriendProfileLayoutTests: XCTestCase {
    func test_topControlsTopPadding_matchesMainSidebarButtonSpacing() {
        XCTAssertEqual(FriendProfileLayout.topControlsTopPadding, 14)
    }

    func test_friendSharedEmptyStateTypography_matchesJourneyMemoryScale() {
        XCTAssertEqual(FriendSharedEmptyStateStyle.titleFontSize, 18)
        XCTAssertEqual(FriendSharedEmptyStateStyle.subtitleFontSize, 14)
        XCTAssertEqual(FriendSharedEmptyStateStyle.verticalSpacing, 16)
    }
}
