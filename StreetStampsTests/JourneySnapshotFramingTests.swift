import XCTest
import CoreLocation
import MapKit
@testable import StreetStamps

final class JourneySnapshotFramingTests: XCTestCase {
    func test_region_containsEntireRouteAfterAspectAdjustment() {
        let coords = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7790, longitude: -122.4140),
            CLLocationCoordinate2D(latitude: 37.7868, longitude: -122.4065),
            CLLocationCoordinate2D(latitude: 37.7928, longitude: -122.4010)
        ]

        let region = JourneySnapshotFraming.region(
            for: coords,
            countryISO2: "US",
            cityKey: "San Francisco|US",
            targetAspectRatio: 1.5
        )

        XCTAssertNotNil(region)
        for coord in coords {
            XCTAssertTrue(regionContains(region, coordinate: coord), "Region should contain \(coord)")
        }
    }

    func test_region_paddingStaysBoundedForTallRoute() {
        let coords = [
            CLLocationCoordinate2D(latitude: 40.0000, longitude: -73.0000),
            CLLocationCoordinate2D(latitude: 40.1200, longitude: -72.9850)
        ]

        let region = JourneySnapshotFraming.region(
            for: coords,
            countryISO2: "US",
            cityKey: "Test|US",
            targetAspectRatio: 1.5
        )

        XCTAssertNotNil(region)
        XCTAssertLessThanOrEqual(region!.span.latitudeDelta, 0.16)
        XCTAssertLessThanOrEqual(region!.span.longitudeDelta, 0.21)
    }

    private func regionContains(_ region: MKCoordinateRegion?, coordinate: CLLocationCoordinate2D) -> Bool {
        guard let region else { return false }
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        return coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon
    }
}
