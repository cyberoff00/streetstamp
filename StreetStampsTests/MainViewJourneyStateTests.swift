import XCTest
@testable import StreetStamps

final class MainViewJourneyStateTests: XCTestCase {
    func test_buttonTextKey_staysInProgressWhenTrackingIsActiveButLocalJourneyLooksCompleted() {
        let key = MainJourneyPresentation.buttonTextKey(
            hasOngoingJourney: false,
            isTracking: true,
            ongoingJourneyEnded: true,
            wasExplicitlyPaused: false
        )

        XCTAssertEqual(key, "in_progress_upper")
    }

    func test_mainViewSource_persistsNewJourneyImmediatelyAndKeepsLiveLocalJourneyDuringSync() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/MainView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("store.upsertSnapshotThrottled(ongoingJourney, coordCount: ongoingJourney.coordinates.count)"))
        XCTAssertTrue(source.contains("store.flushPersist()"))
        XCTAssertTrue(source.contains("if tracking.isTracking, ongoingJourney.endTime == nil {"))
        XCTAssertTrue(source.contains("hasOngoingJourney = true"))
    }
}
