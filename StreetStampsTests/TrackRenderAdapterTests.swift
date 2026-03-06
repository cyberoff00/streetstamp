import XCTest
@testable import StreetStamps

final class TrackRenderAdapterTests: XCTestCase {
    func test_lifelogFootprintSampler_placesFootstepsByDistanceNotPointCount() {
        let route: [CLLocationCoordinate2D] = [
            .init(latitude: 0.0, longitude: 0.0),
            .init(latitude: 0.0, longitude: 0.0027) // ~300m
        ]

        let sampled = LifelogFootprintSampler.sample(route: route, stepMeters: 50, gapBreakMeters: 8_000)

        XCTAssertGreaterThanOrEqual(sampled.count, 6)
        XCTAssertLessThanOrEqual(sampled.count, 8)
    }

    func test_lifelogFootprintSampler_breaksAtLargeGap_withoutInterpolatingAcrossJump() {
        let route: [CLLocationCoordinate2D] = [
            .init(latitude: 37.7749, longitude: -122.4194),
            .init(latitude: 37.7750, longitude: -122.4192),
            .init(latitude: 40.7128, longitude: -74.0060) // > 8,000m jump
        ]

        let sampled = LifelogFootprintSampler.sample(route: route, stepMeters: 50, gapBreakMeters: 8_000)

        XCTAssertEqual(sampled.first?.latitude, route.first?.latitude)
        XCTAssertEqual(sampled.last?.latitude, route.last?.latitude)
        XCTAssertFalse(sampled.isEmpty)
        XCTAssertTrue(
            sampled.contains { coord in
                abs(coord.latitude - route[1].latitude) < 0.000_001 &&
                abs(coord.longitude - route[1].longitude) < 0.000_001
            }
        )
    }

    func test_globeUsesTrackRenderAdapter_notFullLifelogSegmentation() {
        let segments: [TrackTileSegment] = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [CoordinateCodable(lat: 37.7749, lon: -122.4194)]
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7754, lon: -122.4190)
                ]
            )
        ]

        let routes = TrackRenderAdapter.globeJourneys(from: segments, countryISO2: "US")
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes.first?.id, "track.tile.segment.passive.0")
        XCTAssertEqual(routes.first?.coordinates.count, 2)
    }

    func test_lifelogMapReadsTilesForViewportAndZoom() throws {
        let userID = "track-render-adapter-test-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = TrackTileStore(paths: paths)
        let passiveEvents = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_060),
                coordinate: CoordinateCodable(lat: 37.7752, lon: -122.4188)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_120),
                coordinate: CoordinateCodable(lat: 40.7128, lon: -74.0060)
            )
        ]

        try store.refresh(
            journeyEvents: [],
            passiveEvents: passiveEvents,
            journeyRevision: 0,
            passiveRevision: 1,
            zoom: 12
        )

        let viewport = TrackTileViewport(
            minLat: 37.70,
            maxLat: 37.82,
            minLon: -122.52,
            maxLon: -122.35
        )
        let visibleSegments = store.tiles(for: viewport, zoom: 12, sourceFilter: [.passive])
        let polyline = TrackRenderAdapter.polylineCoordinates(
            from: visibleSegments,
            source: .passive,
            maxPoints: 300
        )

        XCTAssertFalse(polyline.isEmpty)
        XCTAssertTrue(polyline.allSatisfy { $0.latitude < 39.0 })
    }

    func test_polylineCoordinates_withoutSourceFilter_mergesJourneyAndPassive() {
        let segments: [TrackTileSegment] = [
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7750, lon: -122.4190)
                ]
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7752, lon: -122.4188),
                    CoordinateCodable(lat: 37.7754, lon: -122.4185)
                ]
            )
        ]

        let polyline = TrackRenderAdapter.polylineCoordinates(from: segments, maxPoints: 50)
        XCTAssertEqual(polyline.count, 4)
    }

    func test_polylineCoordinates_withDayFilter_keepsOnlyMatchingSegments() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(24 * 60 * 60)

        let segments: [TrackTileSegment] = [
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7750, lon: -122.4190)
                ],
                startTimestamp: day1,
                endTimestamp: day1.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 40.7128, lon: -74.0060),
                    CoordinateCodable(lat: 40.7132, lon: -74.0050)
                ],
                startTimestamp: day2,
                endTimestamp: day2.addingTimeInterval(60)
            )
        ]

        let day1Polyline = TrackRenderAdapter.polylineCoordinates(from: segments, day: day1, maxPoints: 20)
        XCTAssertEqual(day1Polyline.count, 2)
        XCTAssertTrue(day1Polyline.allSatisfy { $0.latitude < 39.0 })
    }

    func test_polylineCoordinates_withDayFilter_clipsCrossDaySegmentCoordinates() {
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!
        let end = day2.addingTimeInterval(2 * 60 * 60)

        let segment = TrackTileSegment(
            sourceType: .passive,
            coordinates: [
                CoordinateCodable(lat: 10.0, lon: 10.0), // day1
                CoordinateCodable(lat: 11.0, lon: 11.0), // day1
                CoordinateCodable(lat: 12.0, lon: 12.0), // day2
                CoordinateCodable(lat: 13.0, lon: 13.0)  // day2
            ],
            startTimestamp: day1.addingTimeInterval(22 * 60 * 60),
            endTimestamp: end
        )

        let day1Polyline = TrackRenderAdapter.polylineCoordinates(from: [segment], day: day1, maxPoints: 50)
        XCTAssertEqual(day1Polyline.count, 2)
        XCTAssertEqual(day1Polyline.map(\.latitude), [10.0, 11.0])

        let day2Polyline = TrackRenderAdapter.polylineCoordinates(from: [segment], day: day2, maxPoints: 50)
        XCTAssertEqual(day2Polyline.count, 2)
        XCTAssertEqual(day2Polyline.map(\.latitude), [12.0, 13.0])
    }

    func test_rawCoordinates_withoutDownsample_keepsAllPoints() {
        let segments: [TrackTileSegment] = [
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 37.0, lon: -122.0),
                    CoordinateCodable(lat: 37.1, lon: -122.1),
                    CoordinateCodable(lat: 37.2, lon: -122.2)
                ]
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.3, lon: -122.3),
                    CoordinateCodable(lat: 37.4, lon: -122.4)
                ]
            )
        ]

        let raw = TrackRenderAdapter.rawCoordinates(from: segments)
        XCTAssertEqual(raw.count, 5)
        XCTAssertEqual(raw.map(\.latitude), [37.0, 37.1, 37.2, 37.3, 37.4])
    }

    func test_rawCoordinates_withDayFilter_clipsWithoutFurtherDownsample() {
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!
        let end = day2.addingTimeInterval(2 * 60 * 60)

        let segment = TrackTileSegment(
            sourceType: .passive,
            coordinates: [
                CoordinateCodable(lat: 10.0, lon: 10.0),
                CoordinateCodable(lat: 11.0, lon: 11.0),
                CoordinateCodable(lat: 12.0, lon: 12.0),
                CoordinateCodable(lat: 13.0, lon: 13.0)
            ],
            startTimestamp: day1.addingTimeInterval(22 * 60 * 60),
            endTimestamp: end
        )

        let day1Raw = TrackRenderAdapter.rawCoordinates(from: [segment], day: day1)
        XCTAssertEqual(day1Raw.map(\.latitude), [10.0, 11.0])

        let day2Raw = TrackRenderAdapter.rawCoordinates(from: [segment], day: day2)
        XCTAssertEqual(day2Raw.map(\.latitude), [12.0, 13.0])
    }
}
