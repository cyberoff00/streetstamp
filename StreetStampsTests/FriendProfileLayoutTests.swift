import XCTest
@testable import StreetStamps

final class FriendProfileLayoutTests: XCTestCase {
    func test_topControlsTopPadding_matchesMainSidebarButtonSpacing() {
        XCTAssertEqual(FriendProfileLayout.topControlsTopPadding, 14)
    }
}
