import Foundation
import CoreLocation

struct JourneyMemoryLocationResolution: Equatable {
    var coordinate: (Double, Double)
    var status: JourneyMemoryLocationStatus
    var source: JourneyMemoryLocationSource

    static let pending = JourneyMemoryLocationResolution(
        coordinate: (0, 0),
        status: .pending,
        source: .pending
    )

    static func == (lhs: JourneyMemoryLocationResolution, rhs: JourneyMemoryLocationResolution) -> Bool {
        lhs.coordinate.0 == rhs.coordinate.0 &&
        lhs.coordinate.1 == rhs.coordinate.1 &&
        lhs.status.rawValue == rhs.status.rawValue &&
        lhs.source.rawValue == rhs.source.rawValue
    }
}

enum JourneyMemoryLocationResolver {
    static let maxLiveLocationAge: TimeInterval = 15
    static let maxLiveHorizontalAccuracy: CLLocationAccuracy = 65

    static func resolve(
        memoryTimestamp: Date,
        liveLocation: CLLocation?,
        lastKnownLocation: CLLocation?,
        recordedLocations: [CLLocation]
    ) -> JourneyMemoryLocationResolution {
        if let liveLocation, isReliableLiveLocation(liveLocation, for: memoryTimestamp) {
            return JourneyMemoryLocationResolution(
                coordinate: (liveLocation.coordinate.latitude, liveLocation.coordinate.longitude),
                status: .resolved,
                source: .liveGPS
            )
        }

        if let nearestTrackPoint = nearestTrackPoint(to: memoryTimestamp, in: recordedLocations) {
            return JourneyMemoryLocationResolution(
                coordinate: (nearestTrackPoint.coordinate.latitude, nearestTrackPoint.coordinate.longitude),
                status: .fallback,
                source: .trackNearestByTime
            )
        }

        if let lastKnownLocation {
            return JourneyMemoryLocationResolution(
                coordinate: (lastKnownLocation.coordinate.latitude, lastKnownLocation.coordinate.longitude),
                status: .fallback,
                source: .lastKnownLocation
            )
        }

        return .pending
    }

    static func finalize(
        memory: JourneyMemory,
        lastKnownLocation: CLLocation?,
        recordedLocations: [CLLocation]
    ) -> JourneyMemory {
        guard memory.locationStatus == .pending else { return memory }
        let resolved = resolve(
            memoryTimestamp: memory.timestamp,
            liveLocation: nil,
            lastKnownLocation: lastKnownLocation,
            recordedLocations: recordedLocations
        )

        guard resolved.status != .pending else { return memory }

        var updated = memory
        updated.coordinate = resolved.coordinate
        updated.locationStatus = resolved.status
        updated.locationSource = resolved.source
        return updated
    }

    private static func isReliableLiveLocation(_ location: CLLocation, for timestamp: Date) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxLiveHorizontalAccuracy else {
            return false
        }

        return abs(location.timestamp.timeIntervalSince(timestamp)) <= maxLiveLocationAge
    }

    private static func nearestTrackPoint(to timestamp: Date, in recordedLocations: [CLLocation]) -> CLLocation? {
        recordedLocations.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(timestamp)) < abs(rhs.timestamp.timeIntervalSince(timestamp))
        }
    }
}
