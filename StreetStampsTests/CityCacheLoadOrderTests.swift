import XCTest
@testable import StreetStamps

final class CityCacheLoadOrderTests: XCTestCase {
    @MainActor
    func test_cityCacheRebuildsAfterJourneyStoreFinishesLoading() async throws {
        let userID = "citycache-load-order-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        var route = JourneyRoute()
        route.id = "journey-citycache-load-order"
        route.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        route.endTime = Date(timeIntervalSince1970: 1_700_000_600)
        route.cityName = "San Francisco"
        route.currentCity = "San Francisco"
        route.canonicalCity = "San Francisco"
        route.countryISO2 = "US"
        route.startCityKey = "San Francisco|US"
        route.cityKey = "San Francisco|US"
        route.endCityKey = "San Francisco|US"
        route.coordinates = [
            CoordinateCodable(lat: 37.7749, lon: -122.4194),
            CoordinateCodable(lat: 37.7752, lon: -122.4188)
        ]

        let fileStore = JourneysFileStore(baseURL: paths.journeysDir)
        let indexStore = JourneysIndexStore(baseURL: paths.journeysDir)
        try fileStore.finalizeJourney(route)
        try indexStore.replaceIDs([route.id])

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)

        XCTAssertTrue(cityCache.cachedCities.isEmpty)

        journeyStore.load()

        let loaded = await waitUntil(timeout: 1.5) { journeyStore.hasLoaded }
        XCTAssertTrue(loaded)

        let rebuilt = await waitUntil(timeout: 1.5) { !cityCache.cachedCities.isEmpty }
        XCTAssertTrue(rebuilt, "CityCache should rebuild when JourneyStore.hasLoaded becomes true.")
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
}
