import XCTest
@testable import StreetStamps

final class FriendMapCharacterOverlayLayoutTests: XCTestCase {
    func test_layoutFrames_placesCharactersSideBySideInTopRightCluster() {
        let layout = FriendMapCharacterOverlayLayout.makeLayout(in: CGSize(width: 393, height: 852))

        XCTAssertEqual(layout.doorPosition.x, 92, accuracy: 0.01)
        XCTAssertEqual(layout.doorPosition.y, 607, accuracy: 0.01)
        XCTAssertEqual(layout.myStartPosition.x, 92, accuracy: 0.01)
        XCTAssertEqual(layout.myStartPosition.y, 605, accuracy: 0.01)
        XCTAssertEqual(layout.friendPosition.x, 309, accuracy: 0.01)
        XCTAssertEqual(layout.friendPosition.y, 150, accuracy: 0.01)
        XCTAssertEqual(layout.myPosition.x, 239, accuracy: 0.01)
        XCTAssertEqual(layout.myPosition.y, 150, accuracy: 0.01)
        XCTAssertEqual(layout.bubblePosition.x, 252, accuracy: 0.01)
        XCTAssertEqual(layout.bubblePosition.y, 92, accuracy: 0.01)
    }

    func test_layout_usesLargerCharacterSize() {
        XCTAssertEqual(FriendMapCharacterOverlayLayout.characterSize, 72, accuracy: 0.01)
    }
}
