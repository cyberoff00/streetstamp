import XCTest
@testable import StreetStamps

final class TrackTileStoreTests: XCTestCase {
    func test_store_loadsManifestAndTilesAfterRestart() throws {
        let userID = "track-tiles-test-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyEvents = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_100_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_100_060),
                coordinate: CoordinateCodable(lat: 37.7754, lon: -122.4190)
            )
        ]
        let passiveEvents = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_100_120),
                coordinate: CoordinateCodable(lat: 37.7760, lon: -122.4180)
            )
        ]

        let store1 = TrackTileStore(paths: paths)
        try store1.refresh(
            journeyEvents: journeyEvents,
            passiveEvents: passiveEvents,
            journeyRevision: 3,
            passiveRevision: 5,
            zoom: 10
        )

        let firstRead = store1.tiles(for: nil, zoom: 10)
        XCTAssertFalse(firstRead.isEmpty)

        let store2 = TrackTileStore(paths: paths)
        let secondRead = store2.tiles(for: nil, zoom: 10)
        XCTAssertEqual(firstRead.count, secondRead.count)
        XCTAssertEqual(store2.currentManifest?.journeyRevision, 3)
        XCTAssertEqual(store2.currentManifest?.passiveRevision, 5)
    }

    func test_revisionMismatch_triggersIncrementalRebuild() throws {
        let userID = "track-tiles-test-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyEvents = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_200_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_200_060),
                coordinate: CoordinateCodable(lat: 37.7751, lon: -122.4192)
            )
        ]
        let passiveV1 = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_200_120),
                coordinate: CoordinateCodable(lat: 37.7760, lon: -122.4180)
            )
        ]
        let passiveV2 = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_200_180),
                coordinate: CoordinateCodable(lat: 38.1234, lon: -121.9876)
            )
        ]

        let store = TrackTileStore(paths: paths)
        try store.refresh(
            journeyEvents: journeyEvents,
            passiveEvents: passiveV1,
            journeyRevision: 9,
            passiveRevision: 21,
            zoom: 10
        )

        let journeySegmentsBefore = store.tiles(for: nil, zoom: 10, sourceFilter: [.journey])
        XCTAssertFalse(journeySegmentsBefore.isEmpty)

        try store.refresh(
            journeyEvents: journeyEvents,
            passiveEvents: passiveV2,
            journeyRevision: 9,
            passiveRevision: 22,
            zoom: 10
        )

        let journeySegmentsAfter = store.tiles(for: nil, zoom: 10, sourceFilter: [.journey])
        XCTAssertEqual(journeySegmentsBefore, journeySegmentsAfter)
        XCTAssertEqual(store.currentManifest?.journeyRevision, 9)
        XCTAssertEqual(store.currentManifest?.passiveRevision, 22)

        let passiveSegmentsAfter = store.tiles(for: nil, zoom: 10, sourceFilter: [.passive])
        XCTAssertTrue(passiveSegmentsAfter.flatMap(\.coordinates).contains {
            abs($0.lat - 38.1234) < 0.0001 && abs($0.lon + 121.9876) < 0.0001
        })
    }

    func test_newPassivePoint_updatesOnlyAffectedTiles() throws {
        let userID = "track-tiles-test-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyEvents = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_300_000),
                coordinate: CoordinateCodable(lat: 40.7128, lon: -74.0060)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_300_120),
                coordinate: CoordinateCodable(lat: 40.7132, lon: -74.0050)
            )
        ]

        let passiveV1 = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_300_200),
                coordinate: CoordinateCodable(lat: 40.7140, lon: -74.0040)
            )
        ]
        let passiveV2 = passiveV1 + [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_300_260),
                coordinate: CoordinateCodable(lat: 40.7190, lon: -73.9990)
            )
        ]

        let store = TrackTileStore(paths: paths)
        try store.refresh(
            journeyEvents: journeyEvents,
            passiveEvents: passiveV1,
            journeyRevision: 1,
            passiveRevision: 1,
            zoom: 10
        )
        let beforeJourney = store.tiles(for: nil, zoom: 10, sourceFilter: [.journey])
        let beforePassiveCount = store.tiles(for: nil, zoom: 10, sourceFilter: [.passive])
            .flatMap(\.coordinates)
            .count

        try store.refresh(
            journeyEvents: journeyEvents,
            passiveEvents: passiveV2,
            journeyRevision: 1,
            passiveRevision: 2,
            zoom: 10
        )

        let afterJourney = store.tiles(for: nil, zoom: 10, sourceFilter: [.journey])
        let afterPassiveCount = store.tiles(for: nil, zoom: 10, sourceFilter: [.passive])
            .flatMap(\.coordinates)
            .count

        XCTAssertEqual(beforeJourney, afterJourney)
        XCTAssertGreaterThan(afterPassiveCount, beforePassiveCount)
    }

    func test_manifest_persistsTailSegmentEventsForIncrementalAppend() throws {
        let userID = "track-tiles-tail-manifest-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let passiveEvents = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_300_000),
                coordinate: CoordinateCodable(lat: 40.7140, lon: -74.0040)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_300_060),
                coordinate: CoordinateCodable(lat: 40.7150, lon: -74.0030)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_300_120),
                coordinate: CoordinateCodable(lat: 40.7160, lon: -74.0020)
            )
        ]

        let store = TrackTileStore(paths: paths)
        try store.refresh(
            journeyEvents: [],
            passiveEvents: passiveEvents,
            journeyRevision: 0,
            passiveRevision: 1,
            zoom: 10
        )

        let manifest = try XCTUnwrap(store.currentManifest)
        XCTAssertEqual(manifest.passiveTailEvents?.count, 3)
        XCTAssertEqual(manifest.passiveTailEvents?.last?.coordinate, passiveEvents.last?.coordinate)
    }

    func test_incrementalAppend_rebuildsOnlyTailSegmentForSource() throws {
        let userID = "track-tiles-tail-append-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let base = Date(timeIntervalSince1970: 1_700_500_000)
        let passiveV1 = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: base,
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: base.addingTimeInterval(60),
                coordinate: CoordinateCodable(lat: 37.7751, lon: -122.4191)
            )
        ]
        let passiveV2 = passiveV1 + [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: base.addingTimeInterval(120),
                coordinate: CoordinateCodable(lat: 37.7754, lon: -122.4187)
            )
        ]

        let store = TrackTileStore(paths: paths)
        try store.refresh(
            journeyEvents: [],
            passiveEvents: passiveV1,
            journeyRevision: 0,
            passiveRevision: 1,
            zoom: 10
        )

        let initialSegments = store.tiles(for: nil, zoom: 10, sourceFilter: [.passive])
        XCTAssertEqual(initialSegments.count, 1)
        XCTAssertEqual(initialSegments[0].coordinates.count, 2)

        try store.refresh(
            journeyEvents: [],
            passiveEvents: passiveV2,
            journeyRevision: 0,
            passiveRevision: 2,
            zoom: 10
        )

        let rebuiltSegments = store.tiles(for: nil, zoom: 10, sourceFilter: [.passive])
        XCTAssertEqual(rebuiltSegments.count, 1)
        XCTAssertEqual(rebuiltSegments[0].coordinates.count, 3)
        XCTAssertEqual(store.currentManifest?.passiveTailEvents?.count, 3)
    }

    func test_tiles_withDay_returnsOnlyIndexedDaySegments() throws {
        let userID = "track-tiles-day-index-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(24 * 60 * 60)
        let passiveEvents = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: day1.addingTimeInterval(60),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: day1.addingTimeInterval(120),
                coordinate: CoordinateCodable(lat: 37.7752, lon: -122.4188)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: day2.addingTimeInterval(60),
                coordinate: CoordinateCodable(lat: 40.7128, lon: -74.0060)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: day2.addingTimeInterval(120),
                coordinate: CoordinateCodable(lat: 40.7132, lon: -74.0050)
            )
        ]

        let store = TrackTileStore(paths: paths)
        try store.refresh(
            journeyEvents: [],
            passiveEvents: passiveEvents,
            journeyRevision: 0,
            passiveRevision: 2,
            zoom: 10
        )

        let day1Segments = store.tiles(for: nil, zoom: 10, day: day1, sourceFilter: [.passive])
        let day2Segments = store.tiles(for: nil, zoom: 10, day: day2, sourceFilter: [.passive])

        XCTAssertFalse(day1Segments.isEmpty)
        XCTAssertFalse(day2Segments.isEmpty)
        XCTAssertTrue(day1Segments.flatMap(\.coordinates).allSatisfy { $0.lat < 39.0 })
        XCTAssertTrue(day2Segments.flatMap(\.coordinates).allSatisfy { $0.lat > 39.0 })
    }
}
