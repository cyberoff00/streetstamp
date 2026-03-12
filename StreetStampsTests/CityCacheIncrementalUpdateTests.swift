import XCTest
@testable import StreetStamps

final class CityCacheIncrementalUpdateTests: XCTestCase {
    @MainActor
    func test_applyJourneyMutationAddsCompletedJourneyToOneCity() throws {
        let (cache, _) = try makeCache(userID: "citycache-add-\(UUID().uuidString)")
        let journey = makeJourney(id: "journey-1", cityKey: "Paris|FR", cityName: "Paris", iso: "FR", memoryCount: 2)

        cache.applyJourneyMutation(oldJourney: nil, newJourney: journey)

        XCTAssertEqual(cache.cachedCities.map(\.id), ["Paris|FR"])
        XCTAssertEqual(cache.cachedCities.first?.journeyIds, ["journey-1"])
        XCTAssertEqual(cache.cachedCities.first?.memories, 2)
    }

    @MainActor
    func test_applyJourneyMutationDeletingJourneyOnlyRemovesOldCity() throws {
        let (cache, _) = try makeCache(userID: "citycache-delete-\(UUID().uuidString)")
        let paris = makeJourney(id: "journey-1", cityKey: "Paris|FR", cityName: "Paris", iso: "FR", memoryCount: 2)
        let berlin = makeJourney(id: "journey-2", cityKey: "Berlin|DE", cityName: "Berlin", iso: "DE", memoryCount: 1)

        cache.applyJourneyMutation(oldJourney: nil, newJourney: paris)
        cache.applyJourneyMutation(oldJourney: nil, newJourney: berlin)
        cache.applyJourneyMutation(oldJourney: paris, newJourney: nil)

        XCTAssertEqual(Set(cache.cachedCities.map(\.id)), ["Berlin|DE"])
        XCTAssertEqual(cache.cachedCities.first?.journeyIds, ["journey-2"])
        XCTAssertEqual(cache.cachedCities.first?.memories, 1)
    }

    @MainActor
    func test_applyJourneyMutationMovesJourneyBetweenCities() throws {
        let (cache, _) = try makeCache(userID: "citycache-move-\(UUID().uuidString)")
        let original = makeJourney(id: "journey-1", cityKey: "Paris|FR", cityName: "Paris", iso: "FR", memoryCount: 2)
        let updated = makeJourney(id: "journey-1", cityKey: "Berlin|DE", cityName: "Berlin", iso: "DE", memoryCount: 2)

        cache.applyJourneyMutation(oldJourney: nil, newJourney: original)
        cache.applyJourneyMutation(oldJourney: original, newJourney: updated)

        XCTAssertNil(cache.cachedCities.first(where: { $0.id == "Paris|FR" }))
        XCTAssertEqual(cache.cachedCities.first(where: { $0.id == "Berlin|DE" })?.journeyIds, ["journey-1"])
    }

    @MainActor
    func test_applyJourneyMutationUpdatesMemoryCountWithoutTouchingOtherCity() throws {
        let (cache, _) = try makeCache(userID: "citycache-memories-\(UUID().uuidString)")
        let untouched = makeJourney(id: "journey-2", cityKey: "Tokyo|JP", cityName: "Tokyo", iso: "JP", memoryCount: 5)
        let original = makeJourney(id: "journey-1", cityKey: "Paris|FR", cityName: "Paris", iso: "FR", memoryCount: 1)
        let updated = makeJourney(id: "journey-1", cityKey: "Paris|FR", cityName: "Paris", iso: "FR", memoryCount: 3)

        cache.applyJourneyMutation(oldJourney: nil, newJourney: untouched)
        cache.applyJourneyMutation(oldJourney: nil, newJourney: original)
        cache.applyJourneyMutation(oldJourney: original, newJourney: updated)

        XCTAssertEqual(cache.cachedCities.first(where: { $0.id == "Tokyo|JP" })?.memories, 5)
        XCTAssertEqual(cache.cachedCities.first(where: { $0.id == "Paris|FR" })?.memories, 3)
    }

    @MainActor
    func test_payloadUsesUnifiedDisplayTitleWhenReserveProfileExists() throws {
        let (cache, _) = try makeCache(userID: "citycache-payload-\(UUID().uuidString)")
        let parentRegionKey = "cache-payload-parent-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let journey = makeJourney(
            id: "journey-1",
            cityKey: "Xinyi Township|TW",
            cityName: "Xinyi Township",
            iso: "TW",
            memoryCount: 0
        )

        cache.applyJourneyMutation(oldJourney: nil, newJourney: journey)
        cache.updateCityLevelReserveProfile(
            cityKey: "Xinyi Township|TW",
            level: .locality,
            parentRegionKey: parentRegionKey,
            availableLevels: [
                .locality: "Xinyi Township",
                .admin: "Taiwan"
            ],
            anchor: journey.startCoordinate,
            force: true
        )

        let payload = cache.payload(for: "Xinyi Township|TW")

        XCTAssertEqual(payload?.title, "Taiwan")
    }

    @MainActor
    func test_updateCityLevelReserveProfileRefreshesLabelsEvenWhenReservedLevelAlreadyExists() throws {
        let (cache, _) = try makeCache(userID: "citycache-refresh-levels-\(UUID().uuidString)")
        let journey = makeJourney(
            id: "journey-1",
            cityKey: "London|GB",
            cityName: "London",
            iso: "GB",
            memoryCount: 0
        )

        cache.applyJourneyMutation(oldJourney: nil, newJourney: journey)
        cache.updateCityLevelReserveProfile(
            cityKey: "London|GB",
            level: .locality,
            parentRegionKey: "England|GB",
            availableLevels: [
                .locality: "London",
                .admin: "England"
            ],
            anchor: journey.startCoordinate,
            force: true
        )

        cache.updateCityLevelReserveProfile(
            cityKey: "London|GB",
            level: .locality,
            parentRegionKey: "England|GB",
            availableLevels: [
                .locality: "伦敦",
                .admin: "英格兰"
            ],
            anchor: journey.startCoordinate,
            force: false
        )

        let cached = try XCTUnwrap(cache.cachedCities.first(where: { $0.id == "London|GB" }))
        XCTAssertEqual(cached.reservedLevelRaw, CityPlacemarkResolver.CardLevel.locality.rawValue)
        XCTAssertEqual(cached.reservedAvailableLevelNames?[CityPlacemarkResolver.CardLevel.locality.rawValue], "伦敦")
        XCTAssertEqual(cached.reservedAvailableLevelNames?[CityPlacemarkResolver.CardLevel.admin.rawValue], "英格兰")
        XCTAssertEqual(cached.reservedAvailableLevelNamesLocaleID, Locale.current.identifier)
    }

    @MainActor
    private func makeCache(userID: String) throws -> (CityCache, JourneyStore) {
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()
        let store = JourneyStore(paths: paths)
        let cache = CityCache(paths: paths, journeyStore: store)
        return (cache, store)
    }

    private func makeJourney(
        id: String,
        cityKey: String,
        cityName: String,
        iso: String,
        memoryCount: Int
    ) -> JourneyRoute {
        JourneyRoute(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            cityKey: cityKey,
            canonicalCity: cityName,
            coordinates: [
                CoordinateCodable(lat: 48.8566, lon: 2.3522),
                CoordinateCodable(lat: 48.8570, lon: 2.3530)
            ],
            memories: (0..<memoryCount).map { idx in
                JourneyMemory(
                    id: "\(id)-memory-\(idx)",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(idx)),
                    title: "Memory \(idx)",
                    notes: "",
                    imageData: nil,
                    cityKey: cityKey,
                    cityName: cityName,
                    coordinate: (48.8566, 2.3522),
                    type: .memory
                )
            },
            countryISO2: iso,
            currentCity: cityName,
            cityName: cityName,
            startCityKey: cityKey,
            endCityKey: cityKey
        )
    }
}
