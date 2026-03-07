import XCTest
import MapKit
@testable import StreetStamps

final class LifelogRenderSnapshotTests: XCTestCase {
    func test_daySnapshot_keepsSeparateRuns_forFarAndFootprint() {
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
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60),
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
            ),
            TrackTileSegment(
                sourceType: .journey,
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720),
                coordinates: [
                    CoordinateCodable(lat: 37.7800, lon: -122.4100),
                    CoordinateCodable(lat: 37.7810, lon: -122.4090)
                ]
            )
        ]

        let snapshot = LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: segments
        )

        XCTAssertEqual(snapshot.segments.count, 2)
        XCTAssertEqual(snapshot.farRouteGroups.count, 2)
        XCTAssertEqual(snapshot.footprintGroups.count, 2)
        XCTAssertEqual(snapshot.allDayRenderSnapshot.footprintRuns.count, 2)
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
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60),
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190),
                    CoordinateCodable(lat: 37.7756, lon: -122.4185)
                ]
            ),
            TrackTileSegment(
                sourceType: .journey,
                startTimestamp: day.addingTimeInterval(600),
                endTimestamp: day.addingTimeInterval(720),
                coordinates: [
                    CoordinateCodable(lat: 40.7128, lon: -74.0060),
                    CoordinateCodable(lat: 40.7132, lon: -74.0054)
                ]
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

        XCTAssertEqual(snapshot.footprintRuns.count, 1)
        XCTAssertEqual(snapshot.cachedPathCoordsWGS84.count, 3)
        XCTAssertEqual(snapshot.cachedPathCoordsWGS84.first?.latitude, 37.7749, accuracy: 0.000_001)
    }

    func test_incrementalReusePrefixCount_allowsTailAppendOnly() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            TrackTileSegment(
                sourceType: .passive,
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60),
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
            )
        ]
        let latest = [
            existing[0],
            TrackTileSegment(
                sourceType: .passive,
                startTimestamp: day.addingTimeInterval(120),
                endTimestamp: day.addingTimeInterval(180),
                coordinates: [
                    CoordinateCodable(lat: 37.7760, lon: -122.4181),
                    CoordinateCodable(lat: 37.7764, lon: -122.4178)
                ]
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
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60),
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
            )
        ]
        let latest = [
            TrackTileSegment(
                sourceType: .journey,
                startTimestamp: day,
                endTimestamp: day.addingTimeInterval(60),
                coordinates: [
                    CoordinateCodable(lat: 37.7749, lon: -122.4194),
                    CoordinateCodable(lat: 37.7752, lon: -122.4190)
                ]
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
