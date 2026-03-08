import Foundation
import CoreLocation

enum TrackTileBuilder {
    private static let maxSegmentTimeGap: TimeInterval = 30 * 60
    private static let maxSegmentDistanceGapMeters: CLLocationDistance = 8_000

    static func build(events: [TrackRenderEvent], zoom: Int) -> TrackTileBuildOutput {
        guard !events.isEmpty else {
            return TrackTileBuildOutput(tiles: [:])
        }

        let segments = buildSegments(events: events, zoom: zoom)
        guard !segments.isEmpty else {
            return TrackTileBuildOutput(tiles: [:])
        }

        let z = max(0, min(zoom, 22))
        var tiles: [TrackTileKey: TrackTileBucket] = [:]
        for segment in segments {
            for key in tileKeys(for: segment.coordinates, z: z) {
                var bucket = tiles[key] ?? TrackTileBucket(segments: [])
                bucket.segments.append(segment)
                tiles[key] = bucket
            }
        }

        for key in tiles.keys {
            guard var bucket = tiles[key] else { continue }
            bucket.segments.sort {
                if $0.startTimestamp != $1.startTimestamp {
                    return $0.startTimestamp < $1.startTimestamp
                }
                if $0.endTimestamp != $1.endTimestamp {
                    return $0.endTimestamp < $1.endTimestamp
                }
                return $0.sourceType.rawValue < $1.sourceType.rawValue
            }
            tiles[key] = bucket
        }

        return TrackTileBuildOutput(tiles: tiles)
    }

    static func buildSegments(events: [TrackRenderEvent], zoom: Int) -> [TrackTileSegment] {
        guard !events.isEmpty else { return [] }

        let z = max(0, min(zoom, 22))
        return buildEventRuns(events: events).compactMap { run in
            guard let first = run.first, let last = run.last else { return nil }
            let coordinates = run.map(\.coordinate)
            let simplified = simplify(coordinates: coordinates, zoom: z)
            guard !simplified.isEmpty else { return nil }

            return TrackTileSegment(
                id: segmentID(
                    source: first.sourceType,
                    startTimestamp: first.timestamp,
                    endTimestamp: last.timestamp,
                    coordinates: simplified
                ),
                sourceType: first.sourceType,
                coordinates: simplified,
                startTimestamp: first.timestamp,
                endTimestamp: last.timestamp
            )
        }
    }

    static func tailEvents(events: [TrackRenderEvent]) -> [TrackRenderEvent] {
        buildEventRuns(events: events).last ?? []
    }

    private static func tileKey(for coord: CoordinateCodable, z: Int) -> TrackTileKey {
        let n = Double(1 << z)
        let xRaw = ((coord.lon + 180.0) / 360.0) * n
        let safeLat = min(max(coord.lat, -85.0511), 85.0511)
        let latRad = safeLat * .pi / 180.0
        let yRaw = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n

        let x = min(max(Int(xRaw.rounded(.down)), 0), Int(n) - 1)
        let y = min(max(Int(yRaw.rounded(.down)), 0), Int(n) - 1)
        return TrackTileKey(z: z, x: x, y: y)
    }

    private static func simplificationStride(for zoom: Int) -> Int {
        switch zoom {
        case ...5:
            return 8
        case 6...8:
            return 4
        case 9...11:
            return 1
        default:
            return 1
        }
    }

    private static func simplify(coordinates: [CoordinateCodable], zoom: Int) -> [CoordinateCodable] {
        let stride = simplificationStride(for: zoom)
        guard stride > 1, coordinates.count > 2 else {
            return coordinates
        }

        let lastIndex = coordinates.count - 1
        var out: [CoordinateCodable] = []
        out.reserveCapacity((coordinates.count / stride) + 2)

        for (index, coordinate) in coordinates.enumerated() {
            if index == 0 || index == lastIndex || index % stride == 0 {
                out.append(coordinate)
            }
        }

        if out.last != coordinates[lastIndex] {
            out.append(coordinates[lastIndex])
        }

        return out
    }

    private static func shouldStartNewSegment(after previous: TrackRenderEvent, before next: TrackRenderEvent) -> Bool {
        if previous.sourceType != next.sourceType {
            return true
        }
        if next.timestamp.timeIntervalSince(previous.timestamp) > maxSegmentTimeGap {
            return true
        }

        let previousLocation = CLLocation(latitude: previous.coordinate.lat, longitude: previous.coordinate.lon)
        let nextLocation = CLLocation(latitude: next.coordinate.lat, longitude: next.coordinate.lon)
        return nextLocation.distance(from: previousLocation) > maxSegmentDistanceGapMeters
    }

    private static func buildEventRuns(events: [TrackRenderEvent]) -> [[TrackRenderEvent]] {
        guard !events.isEmpty else { return [] }

        let sortedEvents = events.sorted(by: stableEventOrdering)
        var built: [[TrackRenderEvent]] = []
        var currentRun: [TrackRenderEvent] = []

        func flushCurrentRun() {
            guard !currentRun.isEmpty else { return }
            built.append(currentRun)
            currentRun.removeAll(keepingCapacity: true)
        }

        for event in sortedEvents {
            guard let previous = currentRun.last else {
                currentRun = [event]
                continue
            }

            if shouldStartNewSegment(after: previous, before: event) {
                flushCurrentRun()
                currentRun = [event]
                continue
            }

            currentRun.append(event)
        }

        flushCurrentRun()
        return built
    }

    private static func tileKeys(for coordinates: [CoordinateCodable], z: Int) -> Set<TrackTileKey> {
        guard !coordinates.isEmpty else { return [] }
        return Set(coordinates.map { tileKey(for: $0, z: z) })
    }

    private static func segmentID(
        source: TrackSourceType,
        startTimestamp: Date,
        endTimestamp: Date,
        coordinates: [CoordinateCodable]
    ) -> String {
        let first = coordinates.first ?? CoordinateCodable(lat: 0, lon: 0)
        let last = coordinates.last ?? first
        return [
            source.rawValue,
            String(Int(startTimestamp.timeIntervalSince1970)),
            String(Int(endTimestamp.timeIntervalSince1970)),
            String(coordinates.count),
            String(format: "%.6f", first.lat),
            String(format: "%.6f", first.lon),
            String(format: "%.6f", last.lat),
            String(format: "%.6f", last.lon)
        ].joined(separator: "|")
    }

    private static func stableEventOrdering(_ lhs: TrackRenderEvent, _ rhs: TrackRenderEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.sourceType != rhs.sourceType {
            return lhs.sourceType.rawValue < rhs.sourceType.rawValue
        }
        if lhs.coordinate.lat != rhs.coordinate.lat {
            return lhs.coordinate.lat < rhs.coordinate.lat
        }
        return lhs.coordinate.lon < rhs.coordinate.lon
    }
}
