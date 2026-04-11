import XCTest
@testable import StreetStamps
import CoreLocation

/// Measures how long `CityCache.loadInitialData()` blocks the main thread
/// at different data scales. This is the suspected cause of splash animation
/// freezes during cold start.
final class StartupMainThreadBlockingTests: XCTestCase {

    // MARK: - Helpers

    private func makePaths(tag: String) -> StoragePath {
        StoragePath(userID: "startup-block-test-\(tag)-\(UUID().uuidString)")
    }

    private func makeCachedCity(index: Int) -> CachedCity {
        CachedCity(
            id: "City\(index)|XX",
            name: "City\(index)",
            countryISO2: "XX",
            journeyIds: (0..<3).map { "j-\(index)-\($0)" },
            explorations: 3,
            memories: 1,
            boundary: [
                LatLon(lat: 30.0 + Double(index) * 0.1, lon: 121.0),
                LatLon(lat: 30.0 + Double(index) * 0.1, lon: 121.1),
                LatLon(lat: 30.1 + Double(index) * 0.1, lon: 121.1),
                LatLon(lat: 30.1 + Double(index) * 0.1, lon: 121.0)
            ],
            anchor: LatLon(lat: 30.05 + Double(index) * 0.1, lon: 121.05),
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil
        )
    }

    private func makeMembershipIndex(cityCount: Int) -> CityMembershipIndex {
        var entries: [String: CityMembershipEntry] = [:]
        for i in 0..<cityCount {
            let key = "City\(i)|XX"
            entries[key] = CityMembershipEntry(
                cityKey: key,
                cityName: "City\(i)",
                countryISO2: "XX",
                journeyIDs: (0..<3).map { "j-\(i)-\($0)" },
                memories: 1
            )
        }
        return CityMembershipIndex(entries: entries)
    }

    private func seedDisk(paths: StoragePath, cityCount: Int) throws {
        try paths.ensureBaseDirectoriesExist()

        let cities = (0..<cityCount).map { makeCachedCity(index: $0) }
        let data = try JSONEncoder().encode(cities)
        try data.write(to: paths.cityCacheURL, options: .atomic)

        let index = makeMembershipIndex(cityCount: cityCount)
        let indexData = try JSONEncoder().encode(index)
        try indexData.write(to: paths.cityMembershipIndexURL, options: .atomic)
    }

    private func cleanup(paths: StoragePath) {
        try? FileManager.default.removeItem(at: paths.userRoot)
    }

    // MARK: - Tests

    /// Baseline: empty data (new user first launch).
    @MainActor
    func test_loadInitialData_empty() async throws {
        let paths = makePaths(tag: "empty")
        try paths.ensureBaseDirectoriesExist()
        defer { cleanup(paths: paths) }

        let journeyStore = JourneyStore(paths: paths)
        let cache = CityCache(paths: paths, journeyStore: journeyStore)

        let start = CFAbsoluteTimeGetCurrent()
        cache.loadInitialData()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱ loadInitialData (0 cities): \(String(format: "%.2f", elapsed)) ms")
        XCTAssertLessThan(elapsed, 50, "Empty load should be well under 50ms")
    }

    /// Typical user: ~20 cities.
    @MainActor
    func test_loadInitialData_20cities() async throws {
        let paths = makePaths(tag: "20cities")
        defer { cleanup(paths: paths) }
        try seedDisk(paths: paths, cityCount: 20)

        let journeyStore = JourneyStore(paths: paths)
        let cache = CityCache(paths: paths, journeyStore: journeyStore)

        let start = CFAbsoluteTimeGetCurrent()
        cache.loadInitialData()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱ loadInitialData (20 cities): \(String(format: "%.2f", elapsed)) ms")
        XCTAssertLessThan(elapsed, 100, "20 cities should load under 100ms")
    }

    /// Heavy user: ~100 cities.
    @MainActor
    func test_loadInitialData_100cities() async throws {
        let paths = makePaths(tag: "100cities")
        defer { cleanup(paths: paths) }
        try seedDisk(paths: paths, cityCount: 100)

        let journeyStore = JourneyStore(paths: paths)
        let cache = CityCache(paths: paths, journeyStore: journeyStore)

        let start = CFAbsoluteTimeGetCurrent()
        cache.loadInitialData()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱ loadInitialData (100 cities): \(String(format: "%.2f", elapsed)) ms")
        XCTAssertLessThan(elapsed, 200, "100 cities should load under 200ms")
    }

    /// Stress test: 500 cities (unlikely real-world, but shows scaling).
    @MainActor
    func test_loadInitialData_500cities() async throws {
        let paths = makePaths(tag: "500cities")
        defer { cleanup(paths: paths) }
        try seedDisk(paths: paths, cityCount: 500)

        let journeyStore = JourneyStore(paths: paths)
        let cache = CityCache(paths: paths, journeyStore: journeyStore)

        let start = CFAbsoluteTimeGetCurrent()
        cache.loadInitialData()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱ loadInitialData (500 cities): \(String(format: "%.2f", elapsed)) ms")
        // Just measure — no hard assertion. Print the number.
        print("⚠️ 500-city load took \(String(format: "%.1f", elapsed)) ms on main thread")
    }

    /// Measures the full startup sequence main-thread blocking:
    /// bootstrapFileSystemAsync is async but cityCache.loadInitialData() is sync.
    /// This test simulates that pattern to measure total sync blocking time.
    @MainActor
    func test_fullStartupSyncBlockingTime() async throws {
        let paths = makePaths(tag: "fullStartup")
        defer { cleanup(paths: paths) }
        try seedDisk(paths: paths, cityCount: 30)

        // Seed some journey files too
        let fileStore = JourneysFileStore(baseURL: paths.journeysDir)
        let indexStore = JourneysIndexStore(baseURL: paths.journeysDir)
        var journeyIDs: [String] = []
        for i in 0..<10 {
            var route = JourneyRoute()
            route.id = "startup-j-\(i)"
            route.startTime = Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 600))
            route.endTime = Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 600 + 300))
            route.startCityKey = "City\(i % 5)|XX"
            route.cityKey = "City\(i % 5)|XX"
            route.countryISO2 = "XX"
            route.coordinates = (0..<50).map {
                CoordinateCodable(lat: 30.0 + Double($0) * 0.001, lon: 121.0)
            }
            try fileStore.finalizeJourney(route)
            journeyIDs.append(route.id)
        }
        try indexStore.replaceIDs(journeyIDs)

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)

        // Simulate the startup .task sequence on main thread
        let start = CFAbsoluteTimeGetCurrent()

        // Phase 1 parallel loads kick off (these are async, won't block)
        async let journeyLoad: () = journeyStore.loadAsync()

        // This is the synchronous blocker
        cityCache.loadInitialData()
        let syncBlockEnd = CFAbsoluteTimeGetCurrent()

        // Now await the async work
        await journeyLoad
        let totalEnd = CFAbsoluteTimeGetCurrent()

        let syncBlockMs = (syncBlockEnd - start) * 1000
        let totalMs = (totalEnd - start) * 1000

        print("⏱ Main thread SYNC block (loadInitialData): \(String(format: "%.2f", syncBlockMs)) ms")
        print("⏱ Total startup phase 1 (including async loads): \(String(format: "%.2f", totalMs)) ms")
        print("⏱ Sync block is \(String(format: "%.1f", syncBlockMs / totalMs * 100))% of total startup time")

        XCTAssertLessThan(syncBlockMs, 200, "Sync blocking should be under 200ms for 30 cities")
    }
}
