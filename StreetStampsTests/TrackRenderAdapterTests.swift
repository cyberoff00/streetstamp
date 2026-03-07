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

    func test_globePassiveSegments_buildsMultipleSegmentsFromFullEventStream() {
        let events: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_030),
                coordinate: CoordinateCodable(lat: 37.7754, lon: -122.4190)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_060),
                coordinate: CoordinateCodable(lat: 40.7128, lon: -74.0060)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_400_090),
                coordinate: CoordinateCodable(lat: 40.7133, lon: -74.0055)
            )
        ]

        let segments = TrackRenderAdapter.globePassiveSegments(from: events, zoom: 10)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].sourceType, .passive)
        XCTAssertEqual(segments[1].sourceType, .passive)
        XCTAssertEqual(segments[0].coordinates.count, 2)
        XCTAssertEqual(segments[1].coordinates.count, 2)
    }

    @MainActor
    func test_unifiedProvider_mergesJourneyAndPassiveIntoStableOrderedStream() async throws {
        let journeyUserID = "journey-provider-\(UUID().uuidString)"
        let passiveUserID = "passive-provider-\(UUID().uuidString)"
        let journeyPaths = StoragePath(userID: journeyUserID)
        let passivePaths = StoragePath(userID: passiveUserID)
        try? FileManager.default.removeItem(at: journeyPaths.userRoot)
        try? FileManager.default.removeItem(at: passivePaths.userRoot)
        try journeyPaths.ensureBaseDirectoriesExist()
        try passivePaths.ensureBaseDirectoriesExist()

        let journey = JourneyStore(paths: journeyPaths)
        let lifelog = LifelogStore(paths: passivePaths, trackTileRevisionDebounce: 0)

        var route = JourneyRoute()
        route.id = "journey-1"
        route.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        route.endTime = Date(timeIntervalSince1970: 1_700_000_120)
        route.coordinates = [
            CoordinateCodable(lat: 37.7749, lon: -122.4194),
            CoordinateCodable(lat: 37.7752, lon: -122.4190)
        ]
        journey.upsertSnapshotThrottled(route, coordCount: route.coordinates.count)
        lifelog.importExternalTrack(points: [
            (
                coord: CoordinateCodable(lat: 37.7754, lon: -122.4188),
                timestamp: Date(timeIntervalSince1970: 1_700_000_180)
            )
        ])

        let merged = await UnifiedLifelogRenderProvider.trackRenderEventsAsync(
            journeyStore: journey,
            lifelogStore: lifelog
        )

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.sourceType), [.journey, .journey, .passive])
    }

    func test_unifiedProvider_buildsSegmentsFromSnapshotsWithoutStores() {
        let journeyEvents: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_060),
                coordinate: CoordinateCodable(lat: 37.7752, lon: -122.4190)
            )
        ]
        let passiveEvents: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_000_120),
                coordinate: CoordinateCodable(lat: 37.7754, lon: -122.4188)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_000_180),
                coordinate: CoordinateCodable(lat: 37.7758, lon: -122.4184)
            )
        ]

        let segments = UnifiedLifelogRenderProvider.segments(
            journeyEvents: journeyEvents,
            passiveEvents: passiveEvents,
            zoom: TrackRenderAdapter.unifiedRenderZoom
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.sourceType), [.journey, .passive])
        XCTAssertEqual(segments[0].coordinates.count, 2)
        XCTAssertEqual(segments[1].coordinates.count, 2)
    }

    func test_unifiedProvider_filtersSnapshotSegmentsBySourceAndDay() {
        let baseDay = Date(timeIntervalSince1970: 1_700_000_000)
        let nextDay = baseDay.addingTimeInterval(24 * 60 * 60)
        let journeyEvents: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: baseDay,
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: baseDay.addingTimeInterval(60),
                coordinate: CoordinateCodable(lat: 37.7752, lon: -122.4190)
            )
        ]
        let passiveEvents: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: nextDay,
                coordinate: CoordinateCodable(lat: 40.7128, lon: -74.0060)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: nextDay.addingTimeInterval(60),
                coordinate: CoordinateCodable(lat: 40.7132, lon: -74.0054)
            )
        ]

        let segments = UnifiedLifelogRenderProvider.segments(
            journeyEvents: journeyEvents,
            passiveEvents: passiveEvents,
            zoom: TrackRenderAdapter.unifiedRenderZoom,
            day: nextDay,
            sourceFilter: [.passive]
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.sourceType, .passive)
        XCTAssertEqual(segments.first?.coordinates.count, 2)
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

    func test_rawCoordinateRuns_preserveSegmentBoundaries_evenWhenEndpointsAreNearby() {
        let segments: [TrackTileSegment] = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.77490, lon: -122.41940),
                    CoordinateCodable(lat: 37.77496, lon: -122.41934)
                ],
                startTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
                endTimestamp: Date(timeIntervalSince1970: 1_700_000_060)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.77500, lon: -122.41930),
                    CoordinateCodable(lat: 37.77508, lon: -122.41922)
                ],
                startTimestamp: Date(timeIntervalSince1970: 1_700_003_600),
                endTimestamp: Date(timeIntervalSince1970: 1_700_003_660)
            )
        ]

        let runs = TrackRenderAdapter.rawCoordinateRuns(from: segments)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].map(\.latitude), [37.77490, 37.77496])
        XCTAssertEqual(runs[1].map(\.latitude), [37.77500, 37.77508])
    }
}
