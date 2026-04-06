import Foundation
import MapKit
import CoreLocation

// MARK: - Map Engine (internal, derived from MapLayerStyle)

enum MapEngineSetting: String {
    case mapkit
    case mapbox
}

// MARK: - Unified Route Segment

/// Engine-agnostic route segment, replaces all per-view polyline subclasses.
struct MapRouteSegment: Identifiable, Equatable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let isGap: Bool
    let repeatWeight: Double

    static func == (lhs: MapRouteSegment, rhs: MapRouteSegment) -> Bool {
        lhs.id == rhs.id && lhs.isGap == rhs.isGap && lhs.repeatWeight == rhs.repeatWeight && lhs.coordinates.count == rhs.coordinates.count
    }
}

// MARK: - Unified Annotation

enum MapAnnotationKind {
    /// Clustered journey memories (used by MapView + CityDeepView + JourneyRouteDetailView)
    case memoryGroup(key: String, items: [JourneyMemory])
    /// Robot avatar (used by MapView for live tracking)
    case robot
    /// Lifelog avatar with optional mood question (used by LifelogView)
    case lifelogAvatar(showMoodQuestion: Bool)
}

struct MapAnnotationItem: Identifiable {
    let id: String
    var coordinate: CLLocationCoordinate2D
    let kind: MapAnnotationKind
}

// MARK: - Memory Dot Overlay

struct MapCircleOverlay: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
}

// MARK: - Camera Command

struct MapCameraCommand: Identifiable {
    let id: UUID
    let kind: Kind
    let animated: Bool

    enum Kind {
        case setCamera(center: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection, pitch: CGFloat)
        case setRegion(MKCoordinateRegion)
        case fitRect(MKMapRect, padding: UIEdgeInsets)
    }

    static func setCamera(center: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection, pitch: CGFloat, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), kind: .setCamera(center: center, distance: distance, heading: heading, pitch: pitch), animated: animated)
    }

    static func setRegion(_ region: MKCoordinateRegion, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), kind: .setRegion(region), animated: animated)
    }

    static func fitRect(_ rect: MKMapRect, padding: UIEdgeInsets, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), kind: .fitRect(rect, padding: padding), animated: animated)
    }
}

// MARK: - Map Configuration

/// Captures behavioral differences between the 4 map use cases.
struct MapConfiguration {
    /// Whether the user can pan/zoom the map
    let isInteractive: Bool
    /// Journey tracking: altitude-dependent route widths
    let useAltitudeDependentWidths: Bool
    /// Journey tracking: travel mode affects route width
    let travelMode: TravelMode?
    /// CityDeep: memory pins hide/show based on zoom level
    let useZoomAwareVisibility: Bool
    /// CityDeep: green glow dots at memory locations
    let showsMemoryDots: Bool
    /// Journey tracking: 2-point live tail overlay
    let liveTail: [CLLocationCoordinate2D]?
    /// Journey tracking: memory pin compact mode threshold (altitude)
    let memoryCompactAltitude: CLLocationDistance?

    /// Preset for journey tracking map
    static func journeyTracking(travelMode: TravelMode, liveTail: [CLLocationCoordinate2D]) -> MapConfiguration {
        MapConfiguration(
            isInteractive: true,
            useAltitudeDependentWidths: true,
            travelMode: travelMode,
            useZoomAwareVisibility: false,
            showsMemoryDots: false,
            liveTail: liveTail.count == 2 ? liveTail : nil,
            memoryCompactAltitude: 2400
        )
    }

    /// Preset for city deep view map
    static func cityDeep() -> MapConfiguration {
        MapConfiguration(
            isInteractive: true,
            useAltitudeDependentWidths: false,
            travelMode: nil,
            useZoomAwareVisibility: true,
            showsMemoryDots: true,
            liveTail: nil,
            memoryCompactAltitude: nil
        )
    }

    /// Preset for journey detail (read-only single journey)
    static func journeyDetail() -> MapConfiguration {
        MapConfiguration(
            isInteractive: true,
            useAltitudeDependentWidths: false,
            travelMode: nil,
            useZoomAwareVisibility: false,
            showsMemoryDots: false,
            liveTail: nil,
            memoryCompactAltitude: nil
        )
    }

    /// Preset for lifelog passive tracking
    static func lifelog() -> MapConfiguration {
        MapConfiguration(
            isInteractive: true,
            useAltitudeDependentWidths: false,
            travelMode: nil,
            useZoomAwareVisibility: false,
            showsMemoryDots: false,
            liveTail: nil,
            memoryCompactAltitude: nil
        )
    }
}

// MARK: - Callbacks

/// All possible callbacks from the unified map view.
struct MapCallbacks {
    var onSelectMemories: (([JourneyMemory]) -> Void)? = nil
    var onAvatarDoubleTap: (() -> Void)? = nil
    var onMoodTap: (() -> Void)? = nil
    var onGestureStateChanged: ((Bool) -> Void)? = nil
    var onFollowUserChanged: ((Bool) -> Void)? = nil
    var onCameraAltitudeChanged: ((CLLocationDistance) -> Void)? = nil
}
