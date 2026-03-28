import XCTest
@testable import StreetStamps

final class TabSelectionHapticTrackerTests: XCTestCase {
    func test_shouldEmit_isFalse_whenSelectionMatchesCurrentIndex() {
        var tracker = TabSelectionHapticTracker(currentIndex: 1)

        XCTAssertFalse(tracker.shouldEmit(for: 1))
    }

    func test_shouldEmit_isTrue_once_whenSelectionChanges() {
        var tracker = TabSelectionHapticTracker(currentIndex: 0)

        XCTAssertTrue(tracker.shouldEmit(for: 2))
        XCTAssertFalse(tracker.shouldEmit(for: 2))
    }

    func test_shouldEmit_tracksMultipleDistinctSelections() {
        var tracker = TabSelectionHapticTracker(currentIndex: 0)

        XCTAssertTrue(tracker.shouldEmit(for: 1))
        XCTAssertTrue(tracker.shouldEmit(for: 4))
        XCTAssertFalse(tracker.shouldEmit(for: 4))
    }
}
