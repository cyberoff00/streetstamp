import CoreLocation
import XCTest
@testable import StreetStamps

final class LifelogStoreBehaviorTests: XCTestCase {
    private struct PersistedLifelogPoint: Codable {
        let lat: Double
        let lon: Double
        let timestamp: Date
    }

    private struct PersistedLifelogPayload: Codable {
        let points: [PersistedLifelogPoint]
        let coordinates: [CoordinateCodable]
        let isEnabled: Bool
    }

    @MainActor
    func test_archiveJourneyPoints_importsCompletedJourneyOnlyOnce() throws {
        let userID = "lifelog-behavior-test-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = LifelogStore(paths: paths)
        store.load()

        let beforeCount = store.coordinates.count
        var journey = JourneyRoute()
        journey.id = "journey-import-once"
        journey.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        journey.endTime = Date(timeIntervalSince1970: 1_700_000_120)
        journey.coordinates = [
            CoordinateCodable(lat: 1.0, lon: 1.0),
            CoordinateCodable(lat: 2.0, lon: 2.0)
        ]

        store.archiveJourneyPointsIfNeeded(journey)
        let afterFirstImport = store.coordinates.count
        XCTAssertEqual(afterFirstImport, beforeCount + 2)

        store.archiveJourneyPointsIfNeeded(journey)
        XCTAssertEqual(store.coordinates.count, afterFirstImport)
    }

    @MainActor
    func test_load_replaysDeltaLogPoints() async throws {
        let userID = "lifelog-delta-replay-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let deltaURL = paths.lifelogRouteURL
            .deletingPathExtension()
            .appendingPathExtension("delta.jsonl")

        let deltaPoints = [
            CoordinateCodable(lat: 37.7749, lon: -122.4194),
            CoordinateCodable(lat: 37.7752, lon: -122.4188)
        ]
        var line = try JSONEncoder().encode(deltaPoints)
        line.append(0x0A)
        try line.write(to: deltaURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()

        let loaded = await waitUntil(timeout: 1.5) { store.coordinates.count == 2 }
        XCTAssertTrue(loaded, "LifelogStore should replay pending delta points during load.")
    }

    @MainActor
    func test_flushPersistNow_beforeInitialLoadCompletes_doesNotOverwritePersistedTrack() async throws {
        let userID = "lifelog-no-preload-overwrite-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let payload = PersistedLifelogPayload(
            points: [
                PersistedLifelogPoint(
                    lat: 37.7749,
                    lon: -122.4194,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                PersistedLifelogPoint(
                    lat: 37.7752,
                    lon: -122.4188,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_060)
                )
            ],
            coordinates: [
                CoordinateCodable(lat: 37.7749, lon: -122.4194),
                CoordinateCodable(lat: 37.7752, lon: -122.4188)
            ],
            isEnabled: true
        )
        try JSONEncoder().encode(payload).write(to: paths.lifelogRouteURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()
        XCTAssertFalse(store.hasLoaded)

        store.flushPersistNow()

        let loaded = await waitUntil(timeout: 1.5) { store.hasLoaded && store.coordinates.count == 2 }
        XCTAssertTrue(loaded, "Expected persisted track to survive pre-load flush attempts.")

        let data = try Data(contentsOf: paths.lifelogRouteURL)
        let redecoded = try JSONDecoder().decode(PersistedLifelogPayload.self, from: data)
        XCTAssertEqual(redecoded.points.count, 2)
        XCTAssertEqual(redecoded.coordinates.count, 2)
    }

    @MainActor
    func test_trackTileRevision_isDebouncedForBurstPassiveImports() async throws {
        let userID = "lifelog-revision-debounce-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0.20)
        XCTAssertEqual(store.trackTileRevision, 0)

        store.importExternalTrack(points: [
            (coord: CoordinateCodable(lat: 37.7749, lon: -122.4194), timestamp: Date())
        ])
        store.importExternalTrack(points: [
            (coord: CoordinateCodable(lat: 37.7752, lon: -122.4188), timestamp: Date().addingTimeInterval(1))
        ])

        XCTAssertEqual(store.trackTileRevision, 0)

        let bumped = await waitUntil(timeout: 1.0) { store.trackTileRevision == 1 }
        XCTAssertTrue(bumped, "Track tile revision should bump once after debounce window.")
    }

    @MainActor
    func test_load_legacyCoordinateOnlyPayload_doesNotMapToToday() async throws {
        let userID = "lifelog-legacy-coordinate-only-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let json = """
        {
          "coordinates": [
            { "lat": 37.7749, "lon": -122.4194 },
            { "lat": 37.7752, "lon": -122.4188 }
          ],
          "isEnabled": true
        }
        """
        try json.data(using: .utf8)?.write(to: paths.lifelogRouteURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()

        let loaded = await waitUntil(timeout: 1.5) { store.coordinates.count == 2 }
        XCTAssertTrue(loaded)

        let today = Calendar.current.startOfDay(for: Date())
        let todayPolyline = store.mapPolyline(day: today, maxPoints: 50)
        XCTAssertTrue(todayPolyline.isEmpty, "Legacy coordinate-only payload should not be treated as today's route.")
    }

    @MainActor
    func test_load_keepsHistoricalPassivePointsForDayFiltering() async throws {
        let userID = "lifelog-keep-old-passive-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let yesterdayPoint = PersistedLifelogPoint(
            lat: 10.0,
            lon: 10.0,
            timestamp: yesterday.addingTimeInterval(8 * 60 * 60)
        )
        let todayPoint = PersistedLifelogPoint(
            lat: 20.0,
            lon: 20.0,
            timestamp: today.addingTimeInterval(9 * 60 * 60)
        )
        let payload = PersistedLifelogPayload(
            points: [yesterdayPoint, todayPoint],
            coordinates: [
                CoordinateCodable(lat: yesterdayPoint.lat, lon: yesterdayPoint.lon),
                CoordinateCodable(lat: todayPoint.lat, lon: todayPoint.lon)
            ],
            isEnabled: true
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: paths.lifelogRouteURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()

        let loaded = await waitUntil(timeout: 1.5) {
            !store.mapPolyline(day: yesterday, maxPoints: 50).isEmpty &&
            !store.mapPolyline(day: today, maxPoints: 50).isEmpty
        }
        XCTAssertTrue(loaded, "Expected historical passive points to remain queryable by day after load.")

        let todayPolyline = store.mapPolyline(day: today, maxPoints: 50)
        XCTAssertEqual(todayPolyline.count, 1)
        XCTAssertEqual(todayPolyline.first?.latitude, 20.0)

        let yesterdayPolyline = store.mapPolyline(day: yesterday, maxPoints: 50)
        XCTAssertEqual(yesterdayPolyline.count, 1)
        XCTAssertEqual(yesterdayPolyline.first?.latitude, 10.0)
    }

    @MainActor
    func test_load_projectsDefaultCoordinatesToFullHistory() async throws {
        let userID = "lifelog-recent-window-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let points: [PersistedLifelogPoint] = (0..<10).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return PersistedLifelogPoint(
                lat: 30.0 + Double(offset),
                lon: 120.0 + Double(offset),
                timestamp: day.addingTimeInterval(9 * 60 * 60)
            )
        }.reversed()

        let payload = PersistedLifelogPayload(
            points: points,
            coordinates: points.map { CoordinateCodable(lat: $0.lat, lon: $0.lon) },
            isEnabled: true
        )
        try JSONEncoder().encode(payload).write(to: paths.lifelogRouteURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()

        let loadedAll = await waitUntil(timeout: 1.5) { store.coordinates.count == 10 }
        XCTAssertTrue(loadedAll, "Expected default coordinates to keep full history.")

        let oldDay = cal.date(byAdding: .day, value: -9, to: today)!
        let oldDayPolyline = store.mapPolyline(day: oldDay, maxPoints: 20)
        XCTAssertEqual(oldDayPolyline.count, 1, "Older history should still be available via day-based lazy read.")
    }

    @MainActor
    func test_setMood_persistsImmediatelyForFastReload() async throws {
        let userID = "lifelog-mood-immediate-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let day = Calendar.current.startOfDay(for: Date())
        let store = LifelogStore(paths: paths)
        store.setMood("happy", for: day)

        let reloaded = LifelogStore(paths: paths)
        reloaded.load()
        let loaded = await waitUntil(timeout: 1.0) {
            reloaded.mood(for: day) == "happy"
        }
        XCTAssertTrue(loaded, "Mood should persist immediately so app restarts do not lose same-day input.")
    }

    @MainActor
    func test_setMood_writesMoodFileSynchronously() throws {
        let userID = "lifelog-mood-sync-write-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let day = Calendar.current.startOfDay(for: Date())
        let expectedKey = dayKey(day)
        let moodURL = paths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)

        let store = LifelogStore(paths: paths)
        store.setMood("happy", for: day)

        let data = try Data(contentsOf: moodURL)
        let payload = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(payload[expectedKey], "happy")
    }

    @MainActor
    func test_load_usesMoodSideFileWhenPayloadMoodByDayIsEmpty() async throws {
        let userID = "lifelog-mood-sidefile-fallback-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let payloadData = """
        {
          "points": [],
          "coordinates": [],
          "isEnabled": true,
          "moodByDay": {}
        }
        """.data(using: .utf8)!
        try payloadData.write(to: paths.lifelogRouteURL, options: .atomic)

        let day = Calendar.current.startOfDay(for: Date())
        let moodKey = dayKey(day)
        let moodURL = paths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let moodData = try JSONEncoder().encode([moodKey: "happy"])
        try moodData.write(to: moodURL, options: .atomic)

        let store = LifelogStore(paths: paths)
        store.load()

        let loaded = await waitUntil(timeout: 1.0) {
            store.mood(for: day) == "happy"
        }
        XCTAssertTrue(loaded, "Expected side-file mood to survive when payload moodByDay is empty.")
    }

    @MainActor
    func test_bind_ignoresWeakAccuracyPassiveLocation() async throws {
        let userID = "lifelog-weak-accuracy-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0)
        store.load()
        let loaded = await waitUntil(timeout: 1.0) { store.hasLoaded }
        XCTAssertTrue(loaded)

        store.bind(to: LocationHub.shared)
        LocationHub.shared.locationStream.send(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 0,
                horizontalAccuracy: 120,
                verticalAccuracy: 0,
                course: 0,
                speed: 0,
                timestamp: Date()
            )
        )

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(store.coordinates.isEmpty)
    }

    @MainActor
    func test_bind_skipsStationaryClusterUntilMovementResumes() async throws {
        let userID = "lifelog-stationary-cluster-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0)
        store.load()
        let loaded = await waitUntil(timeout: 1.0) { store.hasLoaded }
        XCTAssertTrue(loaded)

        store.bind(to: LocationHub.shared)

        LocationHub.shared.locationStream.send(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 0,
                horizontalAccuracy: 12,
                verticalAccuracy: 0,
                course: 0,
                speed: 0.2,
                timestamp: base
            )
        )
        LocationHub.shared.locationStream.send(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.77493, longitude: -122.41937),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 0,
                course: 0,
                speed: 0.1,
                timestamp: base.addingTimeInterval(190)
            )
        )
        LocationHub.shared.locationStream.send(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.77495, longitude: -122.41935),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 0,
                course: 0,
                speed: 0.1,
                timestamp: base.addingTimeInterval(240)
            )
        )

        let stationarySuppressed = await waitUntil(timeout: 1.0) { store.coordinates.count == 1 }
        XCTAssertTrue(stationarySuppressed)

        LocationHub.shared.locationStream.send(
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.77530, longitude: -122.41890),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 0,
                course: 0,
                speed: 1.6,
                timestamp: base.addingTimeInterval(320)
            )
        )

        let resumed = await waitUntil(timeout: 1.0) { store.coordinates.count == 2 }
        XCTAssertTrue(resumed)
    }

    func test_stepSnapshotCache_readsAndWritesPerDayValues() {
        var cache = LifelogStepSnapshotCache(rawValue: "")
        XCTAssertNil(cache.value(forDayKey: "2026-03-03"))

        cache.setValue(1234, forDayKey: "2026-03-03")
        cache.setValue(2222, forDayKey: "2026-03-04")

        XCTAssertEqual(cache.value(forDayKey: "2026-03-03"), 1234)
        XCTAssertEqual(cache.value(forDayKey: "2026-03-04"), 2222)

        let roundTrip = LifelogStepSnapshotCache(rawValue: cache.rawValue)
        XCTAssertEqual(roundTrip.value(forDayKey: "2026-03-03"), 1234)
        XCTAssertEqual(roundTrip.value(forDayKey: "2026-03-04"), 2222)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        check: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return check()
    }

    private func dayKey(_ day: Date) -> String {
        let start = Calendar.current.startOfDay(for: day)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: start)
    }
}
