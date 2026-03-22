import XCTest
@testable import StreetStamps

final class JourneyPublishStatusTests: XCTestCase {
    func test_idle_journeyID_isNil() {
        let status = JourneyPublishStatus.idle
        XCTAssertNil(status.journeyID)
        XCTAssertFalse(status.isSending)
        XCTAssertFalse(status.isFailed)
    }

    func test_sending_journeyID_returnsID() {
        let status = JourneyPublishStatus.sending(journeyID: "j1", title: "Walk")
        XCTAssertEqual(status.journeyID, "j1")
        XCTAssertTrue(status.isSending)
        XCTAssertFalse(status.isFailed)
    }

    func test_success_journeyID_returnsID() {
        let status = JourneyPublishStatus.success(journeyID: "j2", title: "Hike")
        XCTAssertEqual(status.journeyID, "j2")
        XCTAssertFalse(status.isSending)
        XCTAssertFalse(status.isFailed)
    }

    func test_failed_journeyID_returnsID() {
        let status = JourneyPublishStatus.failed(journeyID: "j3", title: "Run", errorMessage: "timeout")
        XCTAssertEqual(status.journeyID, "j3")
        XCTAssertFalse(status.isSending)
        XCTAssertTrue(status.isFailed)
    }

    func test_equatable_sameCase_isEqual() {
        let a = JourneyPublishStatus.sending(journeyID: "j1", title: "Walk")
        let b = JourneyPublishStatus.sending(journeyID: "j1", title: "Walk")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentCase_isNotEqual() {
        let sending = JourneyPublishStatus.sending(journeyID: "j1", title: "Walk")
        let success = JourneyPublishStatus.success(journeyID: "j1", title: "Walk")
        XCTAssertNotEqual(sending, success)
    }
}
