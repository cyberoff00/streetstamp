import Foundation
import CoreLocation
import MapKit

enum TrackRenderAdapter {
    static let unifiedRenderZoom = 10

    static func globeJourneys(from segments: [TrackTileSegment], countryISO2: String?) -> [JourneyRoute] {
        let filtered = segments.filter { $0.coordinates.count >= 2 }
        guard !filtered.isEmpty else { return [] }

        let lifelogName = L10n.t("tab_lifelog")
        return filtered.enumerated().map { index, segment in
            var route = JourneyRoute()
            route.id = "track.tile.segment.\(segment.sourceType.rawValue).\(index)"
            route.cityName = lifelogName
            route.currentCity = lifelogName
            route.canonicalCity = lifelogName
            route.cityKey = "\(lifelogName)|"
            route.countryISO2 = countryISO2
            route.coordinates = segment.coordinates
            route.thumbnailCoordinates = segment.coordinates
            route.distance = totalDistanceMeters(for: segment.coordinates)
            return route
        }
    }

    static func polylineCoordinates(
        from segments: [TrackTileSegment],
        source: TrackSourceType? = nil,
        day: Date? = nil,
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        let filteredByDay = filter(segments: segments, for: day)
        let merged: [CoordinateCodable]
        if let source {
            merged = filteredByDay
                .filter { $0.sourceType == source }
                .flatMap(\.coordinates)
        } else {
            merged = filteredByDay.flatMap(\.coordinates)
        }

        guard !merged.isEmpty else { return [] }
        let sampled = downsample(coords: merged, maxPoints: max(maxPoints, 2))
        return sampled.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    static func rawCoordinates(
        from segments: [TrackTileSegment],
        source: TrackSourceType? = nil,
        day: Date? = nil
    ) -> [CLLocationCoordinate2D] {
        let filteredByDay = filter(segments: segments, for: day)
        let merged: [CoordinateCodable]
        if let source {
            merged = filteredByDay
                .filter { $0.sourceType == source }
                .flatMap(\.coordinates)
        } else {
            merged = filteredByDay.flatMap(\.coordinates)
        }
        return merged.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    static func viewport(from region: MKCoordinateRegion?) -> TrackTileViewport? {
        guard let region else { return nil }
        let halfLat = region.span.latitudeDelta / 2.0
        let halfLon = region.span.longitudeDelta / 2.0
        return TrackTileViewport(
            minLat: region.center.latitude - halfLat,
            maxLat: region.center.latitude + halfLat,
            minLon: region.center.longitude - halfLon,
            maxLon: region.center.longitude + halfLon
        )
    }

    static func zoomForLifelogLOD(_ lodLevel: Int) -> Int {
        _ = lodLevel
        return unifiedRenderZoom
    }

    private static func filter(segments: [TrackTileSegment], for day: Date?) -> [TrackTileSegment] {
        guard let day else { return segments }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return segments.compactMap { clip($0, start: start, end: end) }
    }

    private static func clip(_ segment: TrackTileSegment, start: Date, end: Date) -> TrackTileSegment? {
        // No temporal overlap with target day.
        if !(segment.startTimestamp < end && segment.endTimestamp >= start) {
            return nil
        }
        // Fully inside target day, keep as-is.
        if segment.startTimestamp >= start && segment.endTimestamp < end {
            return segment
        }

        let coords = segment.coordinates
        guard coords.count >= 2 else { return nil }

        let totalSpan = max(0, segment.endTimestamp.timeIntervalSince(segment.startTimestamp))
        let denom = max(1, coords.count - 1)

        var kept: [CoordinateCodable] = []
        kept.reserveCapacity(coords.count)

        for (index, coord) in coords.enumerated() {
            let t = Double(index) / Double(denom)
            let ts = segment.startTimestamp.addingTimeInterval(totalSpan * t)
            if ts >= start && ts < end {
                kept.append(coord)
            }
        }

        guard kept.count >= 2 else { return nil }
        let clippedStart = max(start, segment.startTimestamp)
        let clippedEnd = min(end, segment.endTimestamp)
        return TrackTileSegment(
            sourceType: segment.sourceType,
            coordinates: kept,
            startTimestamp: clippedStart,
            endTimestamp: clippedEnd
        )
    }

    private static func totalDistanceMeters(for coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for index in 1..<coords.count {
            let a = CLLocation(latitude: coords[index - 1].lat, longitude: coords[index - 1].lon)
            let b = CLLocation(latitude: coords[index].lat, longitude: coords[index].lon)
            total += b.distance(from: a)
        }
        return total
    }

    private static func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints else { return coords }
        let n = coords.count
        let m = maxPoints
        var out: [CoordinateCodable] = []
        out.reserveCapacity(m)

        for i in 0..<m {
            let t = Double(i) / Double(max(m - 1, 1))
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }

        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(out.count)
        for c in out {
            if let last = compact.last, last == c { continue }
            compact.append(c)
        }
        return compact
    }
}
