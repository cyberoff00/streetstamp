import XCTest
@testable import StreetStamps

@MainActor
final class CloudKitRestoreDerivedStateTests: XCTestCase {
    private var cleanupPaths: [StoragePath] = []

    override func tearDownWithError() throws {
        let fm = FileManager.default
        for paths in cleanupPaths {
            if fm.fileExists(atPath: paths.userRoot.path) {
                try? fm.removeItem(at: paths.userRoot)
            }
        }
        cleanupPaths.removeAll()
        try super.tearDownWithError()
    }

    func test_rebuildDerivedCityStateIfNeeded_rebuildsCityCacheAfterJourneyRestore() throws {
        let paths = makePaths()
        try paths.ensureBaseDirectoriesExist()

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)

        let route = JourneyRoute(
            id: "journey-restore-1",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            cityKey: "London|GB",
            canonicalCity: "London",
            coordinates: [
                CoordinateCodable(lat: 51.5074, lon: -0.1278),
                CoordinateCodable(lat: 51.5075, lon: -0.1277)
            ],
            countryISO2: "GB",
            currentCity: "London",
            cityName: "London",
            startCityKey: "London|GB",
            endCityKey: "London|GB"
        )

        journeyStore.addCompletedJourney(route)

        XCTAssertTrue(cityCache.cachedCities.isEmpty)

        CloudKitSyncService.rebuildDerivedCityStateIfNeeded(
            restoredJourneyCount: 1,
            cityCache: cityCache
        )

        XCTAssertEqual(cityCache.cachedCities.map(\.id), ["London|GB"])
    }

    private func makePaths() -> StoragePath {
        let userID = "tests_cloudkit_restore_\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        cleanupPaths.append(paths)
        return paths
    }
}
