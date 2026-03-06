import Foundation

enum TrackTileBuilder {
    static func build(events: [TrackRenderEvent], zoom: Int) -> TrackTileBuildOutput {
        guard !events.isEmpty else {
            return TrackTileBuildOutput(tiles: [:])
        }

        let z = max(0, min(zoom, 22))
        let stride = simplificationStride(for: z)
        let sortedEvents = events.sorted(by: stableEventOrdering)

        var tiles: [TrackTileKey: TrackTileBucket] = [:]
        for source in TrackSourceType.allCases {
            let sourceEvents = sortedEvents.filter { $0.sourceType == source }
            guard !sourceEvents.isEmpty else { continue }

            var currentTileKey: TrackTileKey?
            var currentRun: [TrackRenderEvent] = []

            func flushCurrentRun() {
                guard
                    let key = currentTileKey,
                    !currentRun.isEmpty
                else { return }

                let coordinates = currentRun.map(\.coordinate)
                let simplified = simplify(coordinates: coordinates, stride: stride)
                guard !simplified.isEmpty else {
                    currentRun.removeAll(keepingCapacity: true)
                    return
                }

                let segment = TrackTileSegment(
                    sourceType: source,
                    coordinates: simplified,
                    startTimestamp: currentRun.first?.timestamp ?? .distantPast,
                    endTimestamp: currentRun.last?.timestamp ?? .distantPast
                )
                var bucket = tiles[key] ?? TrackTileBucket(segments: [])
                bucket.segments.append(segment)
                tiles[key] = bucket
                currentRun.removeAll(keepingCapacity: true)
            }

            for event in sourceEvents {
                let key = tileKey(for: event.coordinate, z: z)
                if currentTileKey == nil {
                    currentTileKey = key
                    currentRun = [event]
                    continue
                }

                if key == currentTileKey {
                    currentRun.append(event)
                } else {
                    flushCurrentRun()
                    currentTileKey = key
                    currentRun = [event]
                }
            }

            flushCurrentRun()
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
            return 2
        default:
            return 1
        }
    }

    private static func simplify(coordinates: [CoordinateCodable], stride: Int) -> [CoordinateCodable] {
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
