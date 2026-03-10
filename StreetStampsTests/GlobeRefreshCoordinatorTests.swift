import XCTest
import CoreLocation
@testable import StreetStamps

final class GlobeRefreshCoordinatorTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        GlobeRefreshCoordinator.shared.resetForTesting()
    }

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
            passiveCountryRuns: [
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
            ],
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

    @MainActor
    func test_requestRefresh_incrementsRevision() {
        let coordinator = GlobeRefreshCoordinator.shared

        XCTAssertEqual(coordinator.revision, 0)
        coordinator.requestRefresh(reason: .globePageEntered)
        XCTAssertEqual(coordinator.revision, 1)
        XCTAssertEqual(coordinator.lastReason, .globePageEntered)
    }

    @MainActor
    func test_addCompletedJourney_requestsGlobeRefresh() {
        let userID = "globe_refresh_journey_\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        let store = JourneyStore(paths: paths)
        let coordinator = GlobeRefreshCoordinator.shared
        var journey = JourneyRoute()
        journey.id = "journey-1"
        journey.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        journey.endTime = journey.startTime?.addingTimeInterval(600)
        journey.coordinates = [
            CoordinateCodable(lat: 51.5074, lon: -0.1278),
            CoordinateCodable(lat: 51.5080, lon: -0.1270)
        ]

        XCTAssertEqual(coordinator.revision, 0)
        store.addCompletedJourney(journey)

        XCTAssertEqual(coordinator.revision, 1)
        XCTAssertEqual(coordinator.lastReason, .journeySaved)
    }

    @MainActor
    func test_importExternalTrack_sameDay_doesNotRequestGlobeRefresh() {
        let userID = "globe_refresh_lifelog_same_day_\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0)
        let coordinator = GlobeRefreshCoordinator.shared
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        store.importExternalTrack(
            points: [
                (CoordinateCodable(lat: 51.5074, lon: -0.1278), day),
                (CoordinateCodable(lat: 51.5080, lon: -0.1270), day.addingTimeInterval(60))
            ],
            source: .passiveRecovery
        )
        coordinator.resetForTesting()

        store.importExternalTrack(
            points: [
                (CoordinateCodable(lat: 51.5086, lon: -0.1265), day.addingTimeInterval(120))
            ],
            source: .passiveRecovery
        )

        XCTAssertEqual(coordinator.revision, 0)
        XCTAssertNil(coordinator.lastReason)
    }

    @MainActor
    func test_importExternalTrack_crossDay_requestsGlobeRefreshOnce() {
        let userID = "globe_refresh_lifelog_cross_day_\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        let store = LifelogStore(paths: paths, trackTileRevisionDebounce: 0)
        let coordinator = GlobeRefreshCoordinator.shared
        let dayOne = Date(timeIntervalSince1970: 1_700_000_000)
        let dayTwo = dayOne.addingTimeInterval(24 * 60 * 60)

        store.importExternalTrack(
            points: [
                (CoordinateCodable(lat: 51.5074, lon: -0.1278), dayOne),
                (CoordinateCodable(lat: 51.5080, lon: -0.1270), dayOne.addingTimeInterval(60))
            ],
            source: .passiveRecovery
        )
        coordinator.resetForTesting()

        store.importExternalTrack(
            points: [
                (CoordinateCodable(lat: 48.8566, lon: 2.3522), dayTwo),
                (CoordinateCodable(lat: 48.8570, lon: 2.3530), dayTwo.addingTimeInterval(60))
            ],
            source: .passiveRecovery
        )

        XCTAssertEqual(coordinator.revision, 1)
        XCTAssertEqual(coordinator.lastReason, .passiveDayRolledOver)
    }
}
