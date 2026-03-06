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
    func test_load_projectsDefaultCoordinatesToRecentSevenDaysWhileKeepingOlderDaysLazyReadable() async throws {
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

        let recentProjected = await waitUntil(timeout: 1.5) { store.coordinates.count == 7 }
        XCTAssertTrue(recentProjected, "Expected default coordinates to project recent 7-day window.")

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
