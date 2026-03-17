import XCTest
@testable import StreetStamps

final class LiveTrackingRefreshPolicyTests: XCTestCase {
    func test_coordsSnapshotTick_allowsFirstTickAndThenRequiresFiveSecondGap() {
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(LiveTrackingRefreshPolicy.shouldPersistCoordinateSnapshot(lastPersistedAt: nil, now: start))
        XCTAssertFalse(LiveTrackingRefreshPolicy.shouldPersistCoordinateSnapshot(lastPersistedAt: start, now: start.addingTimeInterval(4.9)))
        XCTAssertTrue(LiveTrackingRefreshPolicy.shouldPersistCoordinateSnapshot(lastPersistedAt: start, now: start.addingTimeInterval(5.0)))
    }

    func test_trackingMode_renderDebounce_isTunedForForegroundCadence() {
        XCTAssertEqual(TrackingModeConfig.sport.renderDebounceInterval, 0.16, accuracy: 0.0001)
        XCTAssertEqual(TrackingModeConfig.daily.renderDebounceInterval, 0.5, accuracy: 0.0001)
    }
}
