import XCTest
import CoreLocation
@testable import StreetStamps

@MainActor
final class TrackingServiceResumeLocationTests: XCTestCase {
    private func makeLocation(
        latitude: Double,
        longitude: Double,
        accuracy: CLLocationAccuracy,
        speed: CLLocationSpeed,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: timestamp
        )
    }

    private func configureDeterministicGapTestKnobs(_ service: TrackingService) {
        service.lockAccuracy = 100
        service.lockConsecutiveCount = 1
        service.foregroundMinDistance = 1
        service.backgroundMinDistance = 1
        service.maxAcceptableAccuracy = 50
        service.weakAccuracyThreshold = 35
        service.gapSecondsThreshold = 30
        service.gapDistanceThreshold = 500
        service.backgroundGapSecondsThreshold = 30
        service.backgroundGapDistanceThreshold = 500
        service.missingGapSecondsThreshold = 10_000
        service.missingGapDistanceThreshold = 50_000
        service.stationaryBaseMinMoveMeters = 1
        service.stationarySpeedThreshold = 0.1
        service.stationaryHoldSeconds = 300
    }

    private func waitForPublishedRender() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    override func tearDown() {
        TrackingService.shared.stopJourney()
        TrackingService.shared.userLocation = nil
        super.tearDown()
    }

    func test_resumeJourney_clearsStaleUserLocation() {
        let service = TrackingService.shared
        service.userLocation = CLLocation(latitude: 51.5074, longitude: -0.1278)

        service.resumeJourney()

        XCTAssertNil(service.userLocation)
    }

    func test_resumeFromPause_clearsStaleUserLocation() {
        let service = TrackingService.shared
        service.resumeJourney()
        service.userLocation = CLLocation(latitude: 48.8566, longitude: 2.3522)
        service.pauseJourney()

        service.resumeFromPause()

        XCTAssertNil(service.userLocation)
    }

    func test_renderUnifiedSegmentsForMap_marksRecoveryAfterDroppedWeakSignalAsDashed() async {
        let service = TrackingService.shared
        service.startNewJourney(mode: .sport)
        configureDeterministicGapTestKnobs(service)

        let baseTime = Date(timeIntervalSince1970: 1_000)
        service.ingest(
            makeLocation(
                latitude: 37.7749,
                longitude: -122.4194,
                accuracy: 8,
                speed: 1.2,
                timestamp: baseTime
            )
        )
        service.ingest(
            makeLocation(
                latitude: 37.7750,
                longitude: -122.4194,
                accuracy: 120,
                speed: 0.5,
                timestamp: baseTime.addingTimeInterval(6)
            )
        )
        service.ingest(
            makeLocation(
                latitude: 37.7767,
                longitude: -122.4194,
                accuracy: 8,
                speed: 4.8,
                timestamp: baseTime.addingTimeInterval(22)
            )
        )

        await waitForPublishedRender()

        XCTAssertTrue(
            service.renderUnifiedSegmentsForMap.contains { $0.style == .dashed },
            "Expected a dashed recovery bridge after a dropped weak-signal interval."
        )
    }

    func test_renderUnifiedSegmentsForMap_keepsMinimalMovementAfterDelaySolid() async {
        let service = TrackingService.shared
        service.startNewJourney(mode: .sport)
        configureDeterministicGapTestKnobs(service)

        let baseTime = Date(timeIntervalSince1970: 2_000)
        service.ingest(
            makeLocation(
                latitude: 37.7749,
                longitude: -122.4194,
                accuracy: 8,
                speed: 1.2,
                timestamp: baseTime
            )
        )
        service.ingest(
            makeLocation(
                latitude: 37.7750,
                longitude: -122.4194,
                accuracy: 120,
                speed: 0.5,
                timestamp: baseTime.addingTimeInterval(6)
            )
        )
        service.ingest(
            makeLocation(
                latitude: 37.77497,
                longitude: -122.4194,
                accuracy: 8,
                speed: 1.0,
                timestamp: baseTime.addingTimeInterval(22)
            )
        )

        await waitForPublishedRender()

        XCTAssertFalse(
            service.renderUnifiedSegmentsForMap.contains { $0.style == .dashed },
            "Expected minimal movement after a delay to avoid generating a dashed gap."
        )
    }

    func test_renderUnifiedSegmentsForMap_keepsLargeMissingSegmentDashed() async {
        let service = TrackingService.shared
        service.startNewJourney(mode: .sport)
        configureDeterministicGapTestKnobs(service)

        let baseTime = Date(timeIntervalSince1970: 3_000)
        service.ingest(
            makeLocation(
                latitude: 37.7749,
                longitude: -122.4194,
                accuracy: 8,
                speed: 1.2,
                timestamp: baseTime
            )
        )
        service.ingest(
            makeLocation(
                latitude: 38.3249,
                longitude: -122.4194,
                accuracy: 8,
                speed: 40,
                timestamp: baseTime.addingTimeInterval(120)
            )
        )

        await waitForPublishedRender()

        XCTAssertTrue(
            service.renderUnifiedSegmentsForMap.contains { $0.style == .dashed },
            "Expected large missing/migration jumps to remain dashed."
        )
    }

    func test_dailyBackgroundPolicyUsesPowerSavingPath() throws {
        let source = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/TrackingService.swift"
        )

        XCTAssertTrue(source.contains("hub.enterBackgroundPowerSaving()"))
    }

    func test_dailyBackgroundPowerSavingUses50MeterDistanceFilter() throws {
        let source = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SystemLocationSource.swift"
        )

        XCTAssertTrue(source.contains("manager.distanceFilter = 50"))
    }

    func test_sportBackgroundHighFidelityUsesBestAccuracyAnd10MeterDistanceFilter() throws {
        let source = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SystemLocationSource.swift"
        )
        let marker = "func startBackgroundHighFidelity()"
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let block = String(source[start...])

        XCTAssertTrue(block.contains("manager.desiredAccuracy = kCLLocationAccuracyBest"))
        XCTAssertTrue(block.contains("manager.distanceFilter = 10"))
        XCTAssertFalse(block.contains("manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation"))
    }

    func test_headingSensorsAndHeadlightUiAreRemoved() throws {
        let systemLocationSource = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SystemLocationSource.swift"
        )
        let locationSource = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/LocationSource.swift"
        )
        let locationHub = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/LocationHub.swift"
        )
        let trackingService = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/TrackingService.swift"
        )
        let mapView = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/MapView.swift"
        )
        let lifelogView = try String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/LifelogView.swift"
        )

        XCTAssertFalse(systemLocationSource.contains("startUpdatingHeading()"))
        XCTAssertFalse(systemLocationSource.contains("didUpdateHeading"))
        XCTAssertFalse(locationSource.contains("headingPublisher"))
        XCTAssertFalse(locationHub.contains("headingDegrees"))
        XCTAssertFalse(trackingService.contains("headingDegrees"))
        XCTAssertFalse(mapView.contains("AvatarHeadlightConeView"))
        XCTAssertFalse(mapView.contains("headingDegrees: tracking.headingDegrees"))
        XCTAssertFalse(lifelogView.contains("AvatarHeadlightConeView"))
        XCTAssertFalse(lifelogView.contains("currentHeadingDegrees"))
    }
}
