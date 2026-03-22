import XCTest
@testable import StreetStamps

final class FriendsFeedScrollRestoreStateTests: XCTestCase {
    func test_openingEventRecordsLastOpenedEventID() {
        var state = FriendsFeedScrollRestoreState()

        state.recordOpen(eventID: "feed_123")

        XCTAssertEqual(state.lastOpenedEventID, "feed_123")
        XCTAssertNil(state.pendingRestoreEventID)
    }

    func test_navigationReturnCreatesPendingRestoreRequest() {
        var state = FriendsFeedScrollRestoreState()
        state.recordOpen(eventID: "feed_123")

        state.prepareRestoreOnReturn()

        XCTAssertEqual(state.pendingRestoreEventID, "feed_123")
    }

    func test_consumingRestoreClearsPendingRequest() {
        var state = FriendsFeedScrollRestoreState()
        state.recordOpen(eventID: "feed_123")
        state.prepareRestoreOnReturn()

        state.consumeRestoreRequest()

        XCTAssertNil(state.pendingRestoreEventID)
        XCTAssertEqual(state.lastOpenedEventID, "feed_123")
    }
}
