import XCTest
import CoreLocation
@testable import StreetStamps

final class MemoryLocationResolverTests: XCTestCase {
    func test_resolve_prefers_freshAccurateLiveGPS() {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)
        let live = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            timestamp: timestamp.addingTimeInterval(2)
        )
        let track = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: timestamp
        )

        let resolved = JourneyMemoryLocationResolver.resolve(
            memoryTimestamp: timestamp,
            liveLocation: live,
            lastKnownLocation: nil,
            recordedLocations: [track]
        )

        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertEqual(resolved.source, .liveGPS)
        XCTAssertEqual(resolved.coordinate.0, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(resolved.coordinate.1, 2.3522, accuracy: 0.0001)
    }

    func test_resolve_fallsBackToNearestTrackPoint_whenLiveLocationIsWeak() {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)
        let staleLive = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            altitude: 0,
            horizontalAccuracy: 120,
            verticalAccuracy: 50,
            timestamp: timestamp.addingTimeInterval(-120)
        )
        let earlier = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 120.0),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            timestamp: timestamp.addingTimeInterval(-15)
        )
        let nearest = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.1, longitude: 120.1),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            timestamp: timestamp.addingTimeInterval(5)
        )

        let resolved = JourneyMemoryLocationResolver.resolve(
            memoryTimestamp: timestamp,
            liveLocation: staleLive,
            lastKnownLocation: nil,
            recordedLocations: [earlier, nearest]
        )

        XCTAssertEqual(resolved.status, .fallback)
        XCTAssertEqual(resolved.source, .trackNearestByTime)
        XCTAssertEqual(resolved.coordinate.0, 35.1, accuracy: 0.0001)
        XCTAssertEqual(resolved.coordinate.1, 120.1, accuracy: 0.0001)
    }

    func test_resolve_fallsBackToLastKnownLocation_whenTrackIsUnavailable() {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)
        let lastKnown = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            timestamp: timestamp.addingTimeInterval(-30)
        )

        let resolved = JourneyMemoryLocationResolver.resolve(
            memoryTimestamp: timestamp,
            liveLocation: nil,
            lastKnownLocation: lastKnown,
            recordedLocations: []
        )

        XCTAssertEqual(resolved.status, .fallback)
        XCTAssertEqual(resolved.source, .lastKnownLocation)
        XCTAssertEqual(resolved.coordinate.0, 51.5072, accuracy: 0.0001)
        XCTAssertEqual(resolved.coordinate.1, -0.1276, accuracy: 0.0001)
    }

    func test_resolve_returnsPending_whenNoLocationSourceExists() {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)

        let resolved = JourneyMemoryLocationResolver.resolve(
            memoryTimestamp: timestamp,
            liveLocation: nil,
            lastKnownLocation: nil,
            recordedLocations: []
        )

        XCTAssertEqual(resolved, .pending)
    }

    func test_finalize_updatesPendingMemory_whenFallbackExists() {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)
        let pendingMemory = JourneyMemory(
            id: "memory-1",
            timestamp: timestamp,
            title: "Tunnel",
            notes: "Signal was weak",
            imageData: nil,
            coordinate: (0, 0),
            type: .memory,
            locationStatus: .pending,
            locationSource: .pending
        )
        let track = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: timestamp.addingTimeInterval(4)
        )

        let finalized = JourneyMemoryLocationResolver.finalize(
            memory: pendingMemory,
            lastKnownLocation: nil,
            recordedLocations: [track]
        )

        XCTAssertEqual(finalized.locationStatus, .fallback)
        XCTAssertEqual(finalized.locationSource, .trackNearestByTime)
        XCTAssertEqual(finalized.coordinate.0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(finalized.coordinate.1, -122.4194, accuracy: 0.0001)
    }
}
