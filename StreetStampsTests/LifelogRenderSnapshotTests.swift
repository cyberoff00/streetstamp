import XCTest
import MapKit
@testable import StreetStamps

final class LifelogRenderSnapshotTests: XCTestCase {
    func test_daySnapshot_passiveCountryRuns_splitAndConvertOnlyConfirmedChinaRuns() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "GB",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 51.5074, lon: -0.1278),
                    CoordinateCodable(lat: 51.5078, lon: -0.1270),
                    CoordinateCodable(lat: 39.9042, lon: 116.4074),
                    CoordinateCodable(lat: 39.9046, lon: 116.4080)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(180)
            )
        ]
        let passiveCountryRuns = [
            LifelogAttributedCoordinateRun(
                sourceType: .passive,
                coordsWGS84: [
                    CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
                    CLLocationCoordinate2D(latitude: 51.5078, longitude: -0.1270)
                ],
                countryISO2: "GB",
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            LifelogAttributedCoordinateRun(
                sourceType: .passive,
                coordsWGS84: [
                    CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
                    CLLocationCoordinate2D(latitude: 39.9046, longitude: 116.4080)
                ],
                countryISO2: "CN",
                startTimestamp: day.addingTimeInterval(120),
                endTimestamp: day.addingTimeInterval(180)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments,
            passiveCountryRuns: passiveCountryRuns
        )

        XCTAssertEqual(snapshot.farRouteGroups.count, 2)

        XCTAssertEqual(london.first?.latitude ?? 0, 51.5074, accuracy: 0.000_001)
        XCTAssertEqual(london.first?.longitude ?? 0, -0.1278, accuracy: 0.000_001)

        let expectedGCJ = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074).wgs2gcj
        XCTAssertEqual(beijing.first?.latitude ?? 0, expectedGCJ.latitude, accuracy: 0.000_8)
        XCTAssertEqual(beijing.first?.longitude ?? 0, expectedGCJ.longitude, accuracy: 0.000_8)
    }

    func test_daySnapshot_passiveCountryRuns_leaveUnknownAndNonChinaInWGS84() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "CN",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 34.0522, lon: -118.2437),
                    CoordinateCodable(lat: 34.0525, lon: -118.2430),
                    CoordinateCodable(lat: 48.8566, lon: 2.3522),
                    CoordinateCodable(lat: 48.8569, lon: 2.3529)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(180)
            )
        ]
        let passiveCountryRuns = [
            LifelogAttributedCoordinateRun(
                sourceType: .passive,
                coordsWGS84: [
                    CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
                    CLLocationCoordinate2D(latitude: 34.0525, longitude: -118.2430)
                ],
                countryISO2: nil,
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            LifelogAttributedCoordinateRun(
                sourceType: .passive,
                coordsWGS84: [
                    CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                    CLLocationCoordinate2D(latitude: 48.8569, longitude: 2.3529)
                ],
                countryISO2: "FR",
                startTimestamp: day.addingTimeInterval(120),
                endTimestamp: day.addingTimeInterval(180)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments,
            passiveCountryRuns: passiveCountryRuns
        )

    }

    func test_daySnapshot_requestLevelCountryDoesNotSplitPassivePathWithoutAttributedRuns() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "CN",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 51.5074, lon: -0.1278),
                    CoordinateCodable(lat: 51.5078, lon: -0.1270),
                    CoordinateCodable(lat: 39.9042, lon: 116.4074),
                    CoordinateCodable(lat: 39.9046, lon: 116.4080)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(180)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )

    }

    func test_daySnapshot_keepsSeparateRuns_forFarRoutes() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "US",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 37.7800, lon: -122.4100),
                    CoordinateCodable(lat: 37.7810, lon: -122.4090)
                ],
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )

        XCTAssertEqual(snapshot.segments.count, 2)
        XCTAssertEqual(snapshot.farRouteGroups.count, 2)
        XCTAssertFalse(snapshot.allDayRenderSnapshot.farRouteSegments.isEmpty)
    }

    func test_viewportSnapshot_filtersByViewport_withoutJoiningSeparatedSegments() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "US",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190),
                    CoordinateCodable(lat: 37.7756, lon: -122.4185)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 40.7128, lon: -74.0060),
                    CoordinateCodable(lat: 40.7132, lon: -74.0054)
                ],
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720)
            )
        ]
        let daySnapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )
        let request = LifelogRenderSnapshotRequest.viewportRender(
            selectedDay: day,
            countryISO2: "US"
        )
        let viewport = TrackTileViewport(
            minLat: 37.70,
            maxLat: 37.80,
            minLon: -122.50,
            maxLon: -122.30
        )
        let snapshot = LifelogRenderSnapshotBuilder.buildViewportSnapshot(
            daySnapshot: daySnapshot,
            request: request,
            viewport: viewport
        )

        XCTAssertEqual(snapshot.cachedPathCoordsWGS84.count, 3)
        XCTAssertEqual(snapshot.cachedPathCoordsWGS84.first?.latitude ?? 0, 37.7749, accuracy: 0.000_001)
    }

    func test_daySnapshot_doesNotBridgeAdjacentRuns() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "US",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7800, lon: -122.4100),
                    CoordinateCodable(lat: 37.7810, lon: -122.4090)
                ],
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )
        let rendered = snapshot.allDayRenderSnapshot.farRouteSegments
        let dashed = rendered.filter { $0.style == .dashed }

        XCTAssertTrue(dashed.isEmpty)
    }

    func test_daySnapshot_keepsAllSeparatedRunsDisconnected() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LifelogDaySnapshotKey(
            day: day,
            countryISO2: "US",
            journeyRevision: 11,
            lifelogRevision: 22
        )
        let segments = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7800, lon: -122.4100),
                    CoordinateCodable(lat: 37.7810, lon: -122.4090)
                ],
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720)
            ),
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7747, lon: -122.4192),
                    CoordinateCodable(lat: 37.7745, lon: -122.4195)
                ],
                startTimestamp: day.addingTimeInterval(1_200),
                endTimestamp: day.addingTimeInterval(1_320)
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )
        let rendered = snapshot.allDayRenderSnapshot.farRouteSegments
        let dashed = rendered.filter { $0.style == .dashed }

        XCTAssertTrue(dashed.isEmpty)
    }

    func test_incrementalReusePrefixCount_allowsTailAppendOnly() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            )
        ]
        let latest = [
            existing[0],
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7760, lon: -122.4181),
                    CoordinateCodable(lat: 37.7764, lon: -122.4178)
                ],
                startTimestamp: day.addingTimeInterval(120),
                endTimestamp: day.addingTimeInterval(180)
            )
        ]

        XCTAssertEqual(
            LifelogSegmentIncrementalMergePlanner.reusePrefixCount(
                existing: existing,
                latest: latest
            ),
            1
        )
    }

    func test_incrementalReusePrefixCount_rejects_unsafeReordering() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            TrackTileSegment(
                sourceType: .passive,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            )
        ]
        let latest = [
            TrackTileSegment(
                sourceType: .journey,
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ],
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60)
            )
        ]

        XCTAssertNil(
            LifelogSegmentIncrementalMergePlanner.reusePrefixCount(
                existing: existing,
                latest: latest
            )
        )
    }
}
