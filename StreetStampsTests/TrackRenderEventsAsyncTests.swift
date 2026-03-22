import XCTest
@testable import StreetStamps

final class TrackRenderEventsAsyncTests: XCTestCase {
    @MainActor
    func test_journeyStore_trackRenderEventsAsync_matchesSynchronousOutput() async throws {
        let userID = "journey-events-async-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = JourneyStore(paths: paths)

        var journey = JourneyRoute()
        journey.id = "j1"
        journey.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        journey.endTime = Date(timeIntervalSince1970: 1_700_000_300)
        journey.coordinates = [
            CoordinateCodable(lat: 37.7749, lon: -122.4194),
            CoordinateCodable(lat: 37.7751, lon: -122.4190),
            CoordinateCodable(lat: 37.7755, lon: -122.4184)
        ]

        store.upsertSnapshotThrottled(journey, coordCount: journey.coordinates.count)

        let syncEvents = store.trackRenderEvents()
        let asyncEvents = await store.trackRenderEventsAsync()
        XCTAssertEqual(asyncEvents, syncEvents)
    }

    @MainActor
    func test_lifelogStore_trackRenderEventsAsync_matchesSynchronousOutput() async throws {
        let userID = "lifelog-events-async-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0)
        store.importExternalTrack(points: [
            (
                coord: CoordinateCodable(lat: 37.7749, lon: -122.4194),
                timestamp: Date(timeIntervalSince1970: 1_700_100_000)
            ),
            (
                coord: CoordinateCodable(lat: 37.7753, lon: -122.4187),
                timestamp: Date(timeIntervalSince1970: 1_700_100_060)
            )
        ])

        let syncEvents = store.trackRenderEvents()
        let asyncEvents = await store.trackRenderEventsAsync()
        XCTAssertEqual(asyncEvents, syncEvents)
    }
}
