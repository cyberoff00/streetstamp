import XCTest
@testable import StreetStamps

final class FriendsListScrollRestoreStateTests: XCTestCase {
    func test_openingFriendRecordsLastOpenedFriendID() {
        var state = FriendsListScrollRestoreState()

        state.recordOpen(friendID: "friend_123")

        XCTAssertEqual(state.lastOpenedFriendID, "friend_123")
        XCTAssertNil(state.pendingRestoreFriendID)
    }

    func test_navigationReturnCreatesPendingRestoreRequest() {
        var state = FriendsListScrollRestoreState()
        state.recordOpen(friendID: "friend_123")

        state.prepareRestoreOnReturn()

        XCTAssertEqual(state.pendingRestoreFriendID, "friend_123")
    }

    func test_consumingRestoreClearsPendingRequest() {
        var state = FriendsListScrollRestoreState()
        state.recordOpen(friendID: "friend_123")
        state.prepareRestoreOnReturn()

        state.consumeRestoreRequest()

        XCTAssertNil(state.pendingRestoreFriendID)
        XCTAssertEqual(state.lastOpenedFriendID, "friend_123")
    }
}
