import XCTest
@testable import StreetStamps

final class MapboxGlobeViewRenderStateTests: XCTestCase {
    func test_renderPayload_storesLatestJourneysAndCities() {
        let route = JourneyRoute(
            id: "route-1",
            endTime: Date(timeIntervalSince1970: 1_700_000_000),
            distance: 1200,
            coordinates: [
                CoordinateCodable(lat: 51.5074, lon: -0.1278),
                CoordinateCodable(lat: 51.5078, lon: -0.1270)
            ],
            countryISO2: "GB"
        )
        let city = CachedCity(
            id: "London|GB",
            name: "London",
            countryISO2: "GB",
            journeyIds: ["route-1"],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: LatLon(.init(latitude: 51.5074, longitude: -0.1278)),
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil
        )

        let payload = GlobeRenderPayload(journeys: [route], cachedCities: [city])

        XCTAssertEqual(payload.journeys.map(\.id), ["route-1"])
        XCTAssertEqual(payload.cachedCities.map(\.id), ["London|GB"])
    }
}
