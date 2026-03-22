import XCTest
import MapKit
@testable import StreetStamps

final class LifelogFootprintRenderPlannerTests: XCTestCase {
    func test_runsSignature_changesWhenCountrySplitChangesRunBoundaries() {
        let flattened = [
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            CLLocationCoordinate2D(latitude: 51.5078, longitude: -0.1270),
            CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            CLLocationCoordinate2D(latitude: 39.9046, longitude: 116.4080)
        ]
        let splitRuns = [
            Array(flattened.prefix(2)),
            Array(flattened.suffix(2))
        ]

        XCTAssertNotEqual(
            LifelogFootprintRenderPlanner.runsSignature([flattened]),
            LifelogFootprintRenderPlanner.runsSignature(splitRuns)
        )
    }

    func test_plannedMarkers_clipToViewportBuffer() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        let run = stride(from: -0.12, through: 0.12, by: 0.002).map { lon in
            CLLocationCoordinate2D(latitude: 0, longitude: lon)
        }

        let markers = LifelogFootprintRenderPlanner.plannedMarkers(
            from: [run],
            region: region,
            lodLevel: 3,
            currentCoordinate: nil
        )

        XCTAssertFalse(markers.isEmpty)
        XCTAssertTrue(markers.allSatisfy { $0.coordinate.longitude >= -0.0124 && $0.coordinate.longitude <= 0.0124 })
        XCTAssertTrue(markers.allSatisfy { $0.coordinate.latitude >= -0.0124 && $0.coordinate.latitude <= 0.0124 })
    }

    func test_plannedMarkers_respectLodBudget() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let run = stride(from: 0, through: 399, by: 1).map { idx in
            CLLocationCoordinate2D(
                latitude: 37.7700 + (Double(idx) * 0.000_02),
                longitude: -122.4240 + (Double(idx) * 0.000_02)
            )
        }

        let markers = LifelogFootprintRenderPlanner.plannedMarkers(
            from: [run],
            region: region,
            lodLevel: 3,
            currentCoordinate: nil
        )

        XCTAssertLessThanOrEqual(markers.count, 140)
        XCTAssertGreaterThan(markers.count, 0)
    }

    func test_viewportCache_reusesPlannedMarkersForSameKey() {
        let cache = LifelogFootprintViewportCache(limit: 4)
        let key = LifelogFootprintViewportCache.Key(
            lodLevel: 3,
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ),
            runsSignature: 42,
            exclusionCoordinate: nil
        )
        let expected = [
            LifelogFootprintProjectedMarker(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                angleDegrees: 12
            )
        ]
        var buildCount = 0

        let first = cache.value(for: key) {
            buildCount += 1
            return expected
        }
        let second = cache.value(for: key) {
            buildCount += 1
            return []
        }

        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
    }
}
