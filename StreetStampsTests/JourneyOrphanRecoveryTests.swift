import XCTest
import CoreLocation
@testable import StreetStamps

/// Covers orphan recovery for **ongoing** journeys. Before the fix,
/// `scanOrphanedIDs` only looked at full `<id>.json` files, so an in-progress
/// journey (meta + delta only, written for hours during an all-day trip) was
/// unrecoverable if its id fell out of `index.json` — the data sat on disk but
/// the app showed nothing. The scan now also keys off `<id>.meta.json`.
final class JourneyOrphanRecoveryTests: XCTestCase {

    private var baseURL: URL!
    private var store: JourneysFileStore!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("orphan-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        store = JourneysFileStore(baseURL: baseURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    private func ongoingRoute(id: String, points: Int) -> JourneyRoute {
        var route = JourneyRoute()
        route.id = id
        route.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        route.endTime = nil // ongoing
        route.trackingMode = .daily
        route.coordinates = (0..<points).map {
            CoordinateCodable(
                lat: 31.0 + Double($0) * 0.0001,
                lon: 121.0 + Double($0) * 0.0001,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)),
                acc: 10
            )
        }
        return route
    }

    func test_scanOrphans_recoversOngoingJourney_fromMetaAndDelta() throws {
        // Simulate an ongoing journey persisted the way JourneyStore does during
        // tracking: a stripped meta snapshot + an append-only delta of coords.
        // No full `<id>.json` exists yet.
        let route = ongoingRoute(id: "ongoing-1", points: 50)
        try store.saveMetaSnapshot(route)
        try store.appendDelta(journeyId: route.id, newCoords: route.coordinates)

        // Index lost this id (the bug scenario).
        let orphans = store.scanOrphanedIDs(knownIDs: [])
        XCTAssertTrue(orphans.contains("ongoing-1"), "Ongoing journey must be recoverable from meta+delta")

        // And it must actually load, with coordinates rebuilt and still ongoing.
        let loaded = try store.loadJourney(id: "ongoing-1")
        XCTAssertNil(loaded.endTime, "Recovered journey should remain ongoing")
        XCTAssertEqual(loaded.coordinates.count, 50, "Delta replay should restore all coordinates")
    }

    func test_scanOrphans_ignoresIndexFile() throws {
        // The index file lives in the same directory; it must never be treated as
        // a journey id.
        try store.saveMetaSnapshot(ongoingRoute(id: "ongoing-2", points: 3))
        // Write a plausible index.json next to it.
        let indexURL = baseURL.appendingPathComponent("index.json")
        try Data("[\"ongoing-2\"]".utf8).write(to: indexURL)

        let orphans = store.scanOrphanedIDs(knownIDs: ["ongoing-2"])
        XCTAssertFalse(orphans.contains("index"), "index.json must not surface as an orphan id")
    }

    func test_scanOrphans_stillRecoversFinalizedFullFile() throws {
        // Regression guard: finalized journeys (full `<id>.json`) must still be found.
        var route = ongoingRoute(id: "done-1", points: 10)
        route.endTime = Date(timeIntervalSince1970: 1_700_000_100)
        try store.finalizeJourney(route) // writes full file, clears meta/delta

        let orphans = store.scanOrphanedIDs(knownIDs: [])
        XCTAssertTrue(orphans.contains("done-1"))
    }
}
