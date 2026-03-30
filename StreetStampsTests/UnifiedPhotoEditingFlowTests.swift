import XCTest
import UIKit
@testable import StreetStamps

final class UnifiedPhotoEditingFlowTests: XCTestCase {
    func test_queueCompletion_keepsEditedAndSkippedItems_only() {
        let first = UIImage()
        let second = UIImage()
        let third = UIImage()
        let editedFirst = UIImage()

        var state = PhotoEditingQueueState(items: [
            .init(id: "1", original: first),
            .init(id: "2", original: second),
            .init(id: "3", original: third),
        ])

        state.completeCurrent(with: editedFirst)
        state.skipCurrent()
        state.discardCurrent()

        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.finalizedItems.count, 2)
        XCTAssertTrue(state.finalizedItems[0] === editedFirst)
        XCTAssertTrue(state.finalizedItems[1] === second)
    }

    func test_primaryActionTitle_usesDoneAll_forLastItem() {
        let state = PhotoEditingQueueState(items: [
            .init(id: "last", original: UIImage())
        ])

        XCTAssertEqual(state.primaryActionTitle, "Done All")
    }
}
