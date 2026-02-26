import Foundation
import CoreLocation
import MapKit

enum JourneyRoutePostProcessor {
    static func processIfNeeded(_ route: JourneyRoute) async -> JourneyRoute {
        guard route.endTime != nil else { return route }
        guard route.coordinates.count >= 2 else { return route }
        guard route.correctedCoordinates.isEmpty || route.matchedCoordinates.isEmpty else { return route }

        var updated = route

        if updated.correctedCoordinates.isEmpty {
            updated.correctedCoordinates = JourneyPostCorrection.correctedCoordinates(for: updated)
        }

        if updated.preferredRouteSource == .raw, !updated.correctedCoordinates.isEmpty {
            updated.preferredRouteSource = .corrected
        }

        if updated.matchedCoordinates.isEmpty {
            let correctedCL = updated.correctedCoordinates.clCoords.filter(CLLocationCoordinate2DIsValid)
            if let matched = await mapMatchIfPossible(coords: correctedCL, trackingMode: updated.trackingMode),
               matched.count >= 2 {
                updated.matchedCoordinates = matched.map { .init(lat: $0.latitude, lon: $0.longitude) }
            }
        }

        if updated.preferredRouteSource != .matched, !updated.matchedCoordinates.isEmpty {
            updated.preferredRouteSource = .matched
        }

        return updated
    }

    private static func mapMatchIfPossible(
        coords: [CLLocationCoordinate2D],
        trackingMode: TrackingMode
    ) async -> [CLLocationCoordinate2D]? {
        guard coords.count >= 2 else { return nil }
        guard let first = coords.first, let last = coords.last else { return nil }

        let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let end = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let straight = start.distance(from: end)

        if straight < 80 || straight > 200_000 { return nil }

        let anchors = evenlySample(coords, maxPoints: 8)
        guard anchors.count >= 2 else { return nil }

        var merged: [CLLocationCoordinate2D] = []
        merged.reserveCapacity(anchors.count * 12)

        for idx in 1..<anchors.count {
            let a = anchors[idx - 1]
            let b = anchors[idx]
            let segmentDistance = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if segmentDistance < 20 {
                continue
            }
            if segmentDistance > 80_000 {
                return nil
            }

            guard let routed = await routeBetween(a, b, trackingMode: trackingMode), routed.count >= 2 else {
                return nil
            }

            if merged.isEmpty {
                merged.append(contentsOf: routed)
            } else {
                merged.append(contentsOf: routed.dropFirst())
            }
        }

        let deduped = dedupeConsecutive(merged)
        return deduped.count >= 2 ? deduped : nil
    }

    private static func routeBetween(
        _ from: CLLocationCoordinate2D,
        _ to: CLLocationCoordinate2D,
        trackingMode: TrackingMode
    ) async -> [CLLocationCoordinate2D]? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.requestsAlternateRoutes = false
        req.transportType = (trackingMode == .sport) ? .walking : .any

        let dir = MKDirections(request: req)
        do {
            let response = try await dir.calculate()
            guard let route = response.routes.first else { return nil }
            return route.polyline.allCoordinates
        } catch {
            return nil
        }
    }

    private static func evenlySample(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard maxPoints >= 2 else { return Array(coords.prefix(1)) }
        guard coords.count > maxPoints else { return coords }

        let n = coords.count
        let m = maxPoints
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(m)
        for i in 0..<m {
            let t = Double(i) / Double(m - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }
        return dedupeConsecutive(out)
    }

    private static func dedupeConsecutive(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !coords.isEmpty else { return [] }
        var out: [CLLocationCoordinate2D] = [coords[0]]
        out.reserveCapacity(coords.count)

        for c in coords.dropFirst() {
            let last = out[out.count - 1]
            let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < 2 { continue }
            out.append(c)
        }
        return out
    }
}

private extension MKPolyline {
    var allCoordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var coords = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
