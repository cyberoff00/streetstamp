import XCTest
import MapKit
@testable import StreetStamps

final class JourneyMemoryMapCoordinateResolverTests: XCTestCase {
    func test_mapCoordinate_prefersMemoryCityKeyOverFallbackCountry() {
        let beijing = JourneyMemory(
            id: "beijing",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            title: "",
            notes: "",
            imageData: nil,
            cityKey: "Beijing|CN",
            cityName: "Beijing",
            coordinate: (39.9042, 116.4074),
            type: .memory
        )
        let paris = JourneyMemory(
            id: "paris",
            timestamp: Date(timeIntervalSince1970: 1_700_000_001),
            title: "",
            notes: "",
            imageData: nil,
            cityKey: "Paris|FR",
            cityName: "Paris",
            coordinate: (48.8566, 2.3522),
            type: .memory
        )

        let mappedBeijing = JourneyMemoryMapCoordinateResolver.mapCoordinate(
            for: beijing,
            fallbackCountryISO2: "CN",
            fallbackCityKey: "SomeJourney|CN"
        )
        let mappedParis = JourneyMemoryMapCoordinateResolver.mapCoordinate(
            for: paris,
            fallbackCountryISO2: "CN",
            fallbackCityKey: "SomeJourney|CN"
        )

        let expectedBeijing = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074).wgs2gcj
        XCTAssertEqual(mappedBeijing.latitude, expectedBeijing.latitude, accuracy: 0.000_8)
        XCTAssertEqual(mappedBeijing.longitude, expectedBeijing.longitude, accuracy: 0.000_8)
        XCTAssertEqual(mappedParis.latitude, 48.8566, accuracy: 0.000_001)
        XCTAssertEqual(mappedParis.longitude, 2.3522, accuracy: 0.000_001)
    }

    func test_mapCoordinate_fallsBackWhenMemoryCityKeyMissing() {
        let memory = JourneyMemory(
            id: "fallback",
            timestamp: Date(timeIntervalSince1970: 1_700_000_002),
            title: "",
            notes: "",
            imageData: nil,
            cityKey: nil,
            cityName: nil,
            coordinate: (39.9042, 116.4074),
            type: .memory
        )

        let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
            for: memory,
            fallbackCountryISO2: "CN",
            fallbackCityKey: "SomeJourney|CN"
        )
        let expected = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074).wgs2gcj

        XCTAssertEqual(mapped.latitude, expected.latitude, accuracy: 0.000_8)
        XCTAssertEqual(mapped.longitude, expected.longitude, accuracy: 0.000_8)
    }
}
