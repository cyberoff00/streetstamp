import XCTest
@testable import StreetStamps

final class CityMembershipIndexTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CityCollectionResolver.resetForTesting()
    }

    func test_encodingAndDecodingPreservesEntries() throws {
        let index = CityMembershipIndex(entries: [
            "Paris|FR": CityMembershipEntry(
                cityKey: "Paris|FR",
                cityName: "Paris",
                countryISO2: "FR",
                journeyIDs: ["journey-1", "journey-2"],
                memories: 3
            )
        ])

        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(CityMembershipIndex.self, from: data)

        XCTAssertEqual(decoded, index)
    }

    func test_applyJourneyMutationAddsRemovesAndMovesJourneyBetweenCities() {
        var index = CityMembershipIndex()
        let original = makeJourney(
            id: "journey-1",
            cityKey: "Paris|FR",
            cityName: "Paris",
            iso: "FR",
            memoryCount: 2
        )

        index.applyJourneyMutation(oldJourney: nil, newJourney: original)

        XCTAssertEqual(index.entries["Paris|FR"]?.journeyIDs, ["journey-1"])
        XCTAssertEqual(index.entries["Paris|FR"]?.explorations, 1)
        XCTAssertEqual(index.entries["Paris|FR"]?.memories, 2)

        let updated = makeJourney(
            id: "journey-1",
            cityKey: "Berlin|DE",
            cityName: "Berlin",
            iso: "DE",
            memoryCount: 4
        )

        index.applyJourneyMutation(oldJourney: original, newJourney: updated)

        XCTAssertNil(index.entries["Paris|FR"])
        XCTAssertEqual(index.entries["Berlin|DE"]?.journeyIDs, ["journey-1"])
        XCTAssertEqual(index.entries["Berlin|DE"]?.explorations, 1)
        XCTAssertEqual(index.entries["Berlin|DE"]?.memories, 4)

        index.applyJourneyMutation(oldJourney: updated, newJourney: nil)

        XCTAssertTrue(index.entries.isEmpty)
    }

    func test_applyJourneyMutationPreservesUntouchedCityTotals() {
        let untouched = CityMembershipEntry(
            cityKey: "Tokyo|JP",
            cityName: "Tokyo",
            countryISO2: "JP",
            journeyIDs: ["journey-a", "journey-b"],
            memories: 5
        )
        var index = CityMembershipIndex(entries: [
            "Tokyo|JP": untouched
        ])

        let oldJourney = makeJourney(
            id: "journey-1",
            cityKey: "Paris|FR",
            cityName: "Paris",
            iso: "FR",
            memoryCount: 1
        )
        let newJourney = makeJourney(
            id: "journey-1",
            cityKey: "Paris|FR",
            cityName: "Paris",
            iso: "FR",
            memoryCount: 3
        )

        index.applyJourneyMutation(oldJourney: oldJourney, newJourney: newJourney)

        XCTAssertEqual(index.entries["Tokyo|JP"], untouched)
        XCTAssertEqual(index.entries["Paris|FR"]?.journeyIDs, ["journey-1"])
        XCTAssertEqual(index.entries["Paris|FR"]?.memories, 3)
    }

    func test_applyJourneyMutationKeepsMembershipAtIdentityCityKey() {
        CityCollectionResolver.setTestingMappings(
            cityToCollection: ["Nanshan District|CN": "Shenzhen|CN"],
            collectionTitles: ["Shenzhen|CN": "Shenzhen"]
        )

        var index = CityMembershipIndex()
        let journey = makeJourney(
            id: "journey-1",
            cityKey: "Nanshan District|CN",
            cityName: "Nanshan District",
            iso: "CN",
            memoryCount: 2
        )

        index.applyJourneyMutation(oldJourney: nil, newJourney: journey)

        XCTAssertEqual(index.entries["Nanshan District|CN"]?.cityKey, "Nanshan District|CN")
        XCTAssertEqual(index.entries["Nanshan District|CN"]?.cityName, "Nanshan District")
        XCTAssertEqual(index.entries["Nanshan District|CN"]?.journeyIDs, ["journey-1"])
        XCTAssertEqual(index.entries["Nanshan District|CN"]?.memories, 2)
        XCTAssertNil(index.entries["Shenzhen|CN"])
    }

    func test_applyJourneyMutationDoesNotPromoteIdentityToPreferredLevelKey() {
        let parentRegionKey = "membership-raw-key-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        var index = CityMembershipIndex()
        let journey = makeJourney(
            id: "journey-raw-key",
            cityKey: "Nanshan District|CN",
            cityName: "Nanshan District",
            iso: "CN",
            memoryCount: 1
        )

        index.applyJourneyMutation(oldJourney: nil, newJourney: journey)

        XCTAssertNotNil(index.entries["Nanshan District|CN"])
        XCTAssertNil(index.entries["Shenzhen|CN"])
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
