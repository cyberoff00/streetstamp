import XCTest
@testable import StreetStamps

final class GlobeRefreshCoordinatorTests: XCTestCase {
    func test_routeResolver_passiveMixedCountrySegments_needIndependentCountryMetadata() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 51.5074, lon: -0.1278),
                    CoordinateCodable(lat: 51.5078, lon: -0.1270)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 39.9042, lon: 116.4074),
                    CoordinateCodable(lat: 39.9046, lon: 116.4080)
                ],
                startTimestamp: day.addingTimeInterval(120),
                endTimestamp: day.addingTimeInterval(180)
            )
        ]

        let resolved = GlobeRouteResolver.resolve(
            externalJourneys: nil,
            summaryJourneys: [],
            segments: segments,
            countryISO2: "CN"
        )

        XCTAssertEqual(Set(resolved.compactMap(\.countryISO2)), Set(["GB", "CN"]), "Expected globe passive routes to preserve independent country attribution instead of inheriting one request-level country.")
    }

    func test_refreshGate_queuesSecondRefreshWhileBusy() {
        var gate = GlobeRefreshGate()

        XCTAssertTrue(gate.startOrQueue())
        XCTAssertFalse(gate.startOrQueue())
        XCTAssertTrue(gate.finish())
        XCTAssertFalse(gate.isRefreshing)
    }

    func test_routeResolver_prefersTileSegments_beforeSummaryJourneys() {
        var summary = JourneyRoute()
        summary.id = "summary-route"
        summary.coordinates = [
            CoordinateCodable(lat: 40.7128, lon: -74.0060),
            CoordinateCodable(lat: 40.7131, lon: -74.0056)
        ]

        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
            )
        ]

        let resolved = GlobeRouteResolver.resolve(
            externalJourneys: nil,
            summaryJourneys: [summary],
            segments: segments,
            countryISO2: "US"
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertTrue(resolved.first?.id.hasPrefix("track.tile.segment.passive.") == true)
    }

    func test_routeResolver_fallsBackToSummaryJourneys_whenSegmentsEmpty() {
        var route = JourneyRoute()
        route.id = "summary-route"
        route.coordinates = [
            CoordinateCodable(lat: 37.7749, lon: -122.4194),
            CoordinateCodable(lat: 37.7752, lon: -122.4190)
        ]

        let resolved = GlobeRouteResolver.resolve(
            externalJourneys: nil,
            summaryJourneys: [route],
            segments: [],
            countryISO2: "US"
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.id, "summary-route")
    }

    func test_shouldFetchUnifiedSegments_whenTileSegmentsEmpty() {
        XCTAssertTrue(GlobeRouteResolver.shouldFetchUnifiedSegments(tileSegments: []))

        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
            )
        ]

        XCTAssertFalse(GlobeRouteResolver.shouldFetchUnifiedSegments(tileSegments: segments))
    }
}
