import Foundation
import CoreLocation
import Combine

final class TrackTileStore: ObservableObject {
    private static let currentSchemaVersion = 5
    private var paths: StoragePath
    private let fm: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageQueue = DispatchQueue(
        label: "ss.tracktiles.store",
        qos: .utility,
        attributes: .concurrent
    )

    private struct IndexedSegment {
        let key: TrackTileKey
        let segment: TrackTileSegment
    }

    private var bucketsByZoom: [Int: [TrackTileKey: TrackTileBucket]] = [:]
    private var dayIndexByZoom: [Int: [String: [IndexedSegment]]] = [:]
    private var _currentManifest: TrackTileManifest?
    @Published private(set) var refreshRevision: Int = 0
    var currentManifest: TrackTileManifest? {
        storageQueue.sync { _currentManifest }
    }

    init(paths: StoragePath, fm: FileManager = .default) {
        self.paths = paths
        self.fm = fm
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        try? _loadFromDisk()
    }

    func rebind(paths: StoragePath) {
        storageQueue.sync(flags: .barrier) {
            self.paths = paths
            self.bucketsByZoom.removeAll(keepingCapacity: true)
            self.dayIndexByZoom.removeAll(keepingCapacity: true)
            self._currentManifest = nil
            try? self._loadFromDisk()
        }
    }

    func refresh(
        journeyEvents: [TrackRenderEvent],
        passiveEvents: [TrackRenderEvent],
        journeyRevision: Int,
        passiveRevision: Int,
        zoom: Int
    ) throws {
        var caughtError: Error?
        var didMutate = false
        storageQueue.sync(flags: .barrier) {
            do {
                let z = max(0, min(zoom, 22))
                try paths.ensureBaseDirectoriesExist()
                try paths.ensureDirectory(paths.trackTilesDir)

                if _currentManifest == nil {
                    try _loadFromDisk()
                }

                let manifest = _currentManifest
                if let manifest,
                   manifest.schemaVersion == Self.currentSchemaVersion,
                   manifest.zoom == z,
                   manifest.journeyRevision == journeyRevision,
                   manifest.passiveRevision == passiveRevision,
                   bucketsByZoom[z] != nil {
                    return
                }

                let previousTiles = bucketsByZoom[z] ?? [:]
                let merged: [TrackTileKey: TrackTileBucket]

                if let manifest,
                   manifest.zoom == z,
                   manifest.schemaVersion == Self.currentSchemaVersion,
                   bucketsByZoom[z] != nil {
                    var updated = bucketsByZoom[z] ?? [:]
                    updated = try refreshSource(
                        .journey,
                        events: journeyEvents,
                        revision: journeyRevision,
                        manifest: manifest,
                        zoom: z,
                        tiles: updated
                    )
                    updated = try refreshSource(
                        .passive,
                        events: passiveEvents,
                        revision: passiveRevision,
                        manifest: manifest,
                        zoom: z,
                        tiles: updated
                    )
                    merged = updated
                } else {
                    let all = journeyEvents + passiveEvents
                    merged = TrackTileBuilder.build(events: all, zoom: z).tiles
                }
                let dayIndex = buildDayIndex(for: merged)

                bucketsByZoom[z] = merged
                dayIndexByZoom[z] = dayIndex
                let nextManifest = TrackTileManifest(
                    schemaVersion: Self.currentSchemaVersion,
                    zoom: z,
                    journeyRevision: journeyRevision,
                    passiveRevision: passiveRevision,
                    journeyEventCount: journeyEvents.count,
                    passiveEventCount: passiveEvents.count,
                    journeyLastEventTimestamp: journeyEvents.last?.timestamp,
                    passiveLastEventTimestamp: passiveEvents.last?.timestamp,
                    journeyLastEventCoord: journeyEvents.last?.coordinate,
                    passiveLastEventCoord: passiveEvents.last?.coordinate,
                    journeyTailEvents: TrackTileBuilder.tailEvents(events: journeyEvents),
                    passiveTailEvents: TrackTileBuilder.tailEvents(events: passiveEvents),
                    updatedAt: Date()
                )
                _currentManifest = nextManifest
                try _persist(
                    tiles: merged,
                    previousTiles: previousTiles,
                    manifest: nextManifest
                )
                didMutate = true
            } catch {
                caughtError = error
            }
        }
        if didMutate {
            DispatchQueue.main.async { [weak self] in
                self?.refreshRevision &+= 1
            }
        }
        if let caughtError { throw caughtError }
    }

    func tiles(
        for viewport: TrackTileViewport?,
        zoom: Int,
        day: Date? = nil,
        sourceFilter: Set<TrackSourceType>? = nil
    ) -> [TrackTileSegment] {
        storageQueue.sync {
            let z = max(0, min(zoom, 22))
            guard let buckets = bucketsByZoom[z] else { return [] }

            let xs: ClosedRange<Int>?
            let ys: ClosedRange<Int>?
            if let viewport {
                xs = tileXRange(minLon: viewport.minLon, maxLon: viewport.maxLon, z: z)
                ys = tileYRange(minLat: viewport.minLat, maxLat: viewport.maxLat, z: z)
            } else {
                xs = nil
                ys = nil
            }

            var out: [TrackTileSegment] = []
            var seenSegmentIDs = Set<String>()
            if let day,
               let dayMap = dayIndexByZoom[z],
               let entries = dayMap[dayKey(for: day)] {
                for entry in entries {
                    if let xs, let ys, !(xs.contains(entry.key.x) && ys.contains(entry.key.y)) {
                        continue
                    }
                    if let sourceFilter, !sourceFilter.contains(entry.segment.sourceType) {
                        continue
                    }
                    if !seenSegmentIDs.insert(entry.segment.id).inserted {
                        continue
                    }
                    out.append(entry.segment)
                }
            } else if let day {
                // Day index not yet built — fallback to timestamp range filter.
                let cal = Calendar.current
                let dayStart = cal.startOfDay(for: day)
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

                let keys: [TrackTileKey]
                if let xs, let ys {
                    keys = buckets.keys.filter { xs.contains($0.x) && ys.contains($0.y) }
                } else {
                    keys = Array(buckets.keys)
                }

                for key in keys {
                    guard let bucket = buckets[key] else { continue }
                    for segment in bucket.segments {
                        if segment.startTimestamp >= dayEnd || segment.endTimestamp < dayStart {
                            continue
                        }
                        if let sourceFilter, !sourceFilter.contains(segment.sourceType) {
                            continue
                        }
                        if !seenSegmentIDs.insert(segment.id).inserted {
                            continue
                        }
                        out.append(segment)
                    }
                }
            } else {
                let keys: [TrackTileKey]
                if let xs, let ys {
                    keys = buckets.keys.filter { xs.contains($0.x) && ys.contains($0.y) }
                } else {
                    keys = Array(buckets.keys)
                }

                for key in keys {
                    guard let bucket = buckets[key] else { continue }
                    let segments: [TrackTileSegment]
                    if let sourceFilter {
                        segments = bucket.segments.filter { sourceFilter.contains($0.sourceType) }
                    } else {
                        segments = bucket.segments
                    }
                    for segment in segments {
                        if !seenSegmentIDs.insert(segment.id).inserted {
                            continue
                        }
                        out.append(segment)
                    }
                }
            }

            out.sort {
                if $0.startTimestamp != $1.startTimestamp {
                    return $0.startTimestamp < $1.startTimestamp
                }
                if $0.endTimestamp != $1.endTimestamp {
                    return $0.endTimestamp < $1.endTimestamp
                }
                return $0.sourceType.rawValue < $1.sourceType.rawValue
            }
            return out
        }
    }

    private func _persist(
        tiles: [TrackTileKey: TrackTileBucket],
        previousTiles: [TrackTileKey: TrackTileBucket],
        manifest: TrackTileManifest
    ) throws {
        let removedKeys = Set(previousTiles.keys).subtracting(Set(tiles.keys))
        for key in removedKeys {
            let fileURL = paths.trackTilesDir.appendingPathComponent(tileFilename(for: key), isDirectory: false)
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: fileURL)
            }
        }

        for key in tiles.keys.sorted(by: sortKeys) {
            guard let bucket = tiles[key] else { continue }
            if previousTiles[key] == bucket {
                continue
            }
            let fileURL = paths.trackTilesDir.appendingPathComponent(tileFilename(for: key), isDirectory: false)
            let data = try encoder.encode(bucket)
            try data.write(to: fileURL, options: .atomic)
        }

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: paths.trackTileManifestURL, options: .atomic)
    }

    private func _loadFromDisk() throws {
        guard fm.fileExists(atPath: paths.trackTileManifestURL.path) else { return }
        let manifestData = try Data(contentsOf: paths.trackTileManifestURL)
        let manifest = try decoder.decode(TrackTileManifest.self, from: manifestData)
        _currentManifest = manifest

        var loaded: [TrackTileKey: TrackTileBucket] = [:]
        guard fm.fileExists(atPath: paths.trackTilesDir.path) else {
            bucketsByZoom[manifest.zoom] = [:]
            dayIndexByZoom[manifest.zoom] = [:]
            return
        }

        let files = try fm.contentsOfDirectory(at: paths.trackTilesDir, includingPropertiesForKeys: nil)
        for fileURL in files where fileURL.pathExtension == "json" && fileURL.lastPathComponent != "manifest.json" {
            guard let key = tileKey(fromFilename: fileURL.deletingPathExtension().lastPathComponent) else { continue }
            let data = try Data(contentsOf: fileURL)
            let bucket = try decoder.decode(TrackTileBucket.self, from: data)
            loaded[key] = bucket
        }
        bucketsByZoom[manifest.zoom] = loaded
        dayIndexByZoom[manifest.zoom] = buildDayIndex(for: loaded)
    }

    private func tileFilename(for key: TrackTileKey) -> String {
        "\(key.z)_\(key.x)_\(key.y).json"
    }

    private func tileKey(fromFilename name: String) -> TrackTileKey? {
        let parts = name.split(separator: "_")
        guard parts.count == 3,
              let z = Int(parts[0]),
              let x = Int(parts[1]),
              let y = Int(parts[2]) else {
            return nil
        }
        return TrackTileKey(z: z, x: x, y: y)
    }

    private func buildDayIndex(for tiles: [TrackTileKey: TrackTileBucket]) -> [String: [IndexedSegment]] {
        var index: [String: [IndexedSegment]] = [:]
        for (key, bucket) in tiles {
            for segment in bucket.segments {
                for day in dayKeys(for: segment) {
                    index[day, default: []].append(IndexedSegment(key: key, segment: segment))
                }
            }
        }
        return index
    }

    private func refreshSource(
        _ source: TrackSourceType,
        events: [TrackRenderEvent],
        revision: Int,
        manifest: TrackTileManifest,
        zoom: Int,
        tiles: [TrackTileKey: TrackTileBucket]
    ) throws -> [TrackTileKey: TrackTileBucket] {
        let currentRevision: Int = {
            switch source {
            case .journey: return manifest.journeyRevision
            case .passive: return manifest.passiveRevision
            }
        }()
        guard currentRevision != revision else { return tiles }

        let previousCount: Int = {
            switch source {
            case .journey: return manifest.journeyEventCount
            case .passive: return manifest.passiveEventCount
            }
        }()
        let previousLastTimestamp: Date? = {
            switch source {
            case .journey: return manifest.journeyLastEventTimestamp
            case .passive: return manifest.passiveLastEventTimestamp
            }
        }()
        let previousLastCoord: CoordinateCodable? = {
            switch source {
            case .journey: return manifest.journeyLastEventCoord
            case .passive: return manifest.passiveLastEventCoord
            }
        }()
        let tailEvents: [TrackRenderEvent] = {
            switch source {
            case .journey: return manifest.journeyTailEvents ?? []
            case .passive: return manifest.passiveTailEvents ?? []
            }
        }()

        if let appended = appendedEventsIfPossible(
            events: events,
            previousCount: previousCount,
            previousLastTimestamp: previousLastTimestamp,
            previousLastCoord: previousLastCoord
        ) {
            guard !appended.isEmpty else { return tiles }
            guard let dirtyStart = tailEvents.first?.timestamp else {
                return rebuildingWholeSource(source, events: events, zoom: zoom, tiles: tiles)
            }

            var updated = removing(source: source, overlappingOrAfter: dirtyStart, from: tiles)
            let rebuiltTail = tailEvents + appended
            let overlay = TrackTileBuilder.build(events: rebuiltTail, zoom: zoom).tiles
            updated = merging(into: updated, with: overlay)
            return updated
        }

        return rebuildingWholeSource(source, events: events, zoom: zoom, tiles: tiles)
    }

    private func rebuildingWholeSource(
        _ source: TrackSourceType,
        events: [TrackRenderEvent],
        zoom: Int,
        tiles: [TrackTileKey: TrackTileBucket]
    ) -> [TrackTileKey: TrackTileBucket] {
        var updated = removing(source: source, overlappingOrAfter: nil, from: tiles)
        let overlay = TrackTileBuilder.build(events: events, zoom: zoom).tiles
        updated = merging(into: updated, with: overlay)
        return updated
    }

    private func removing(
        source: TrackSourceType,
        overlappingOrAfter dirtyStart: Date?,
        from input: [TrackTileKey: TrackTileBucket]
    ) -> [TrackTileKey: TrackTileBucket] {
        var out: [TrackTileKey: TrackTileBucket] = [:]
        for (key, bucket) in input {
            let kept = bucket.segments.filter { segment in
                guard segment.sourceType == source else { return true }
                guard let dirtyStart else { return false }
                return segment.endTimestamp < dirtyStart
            }
            if !kept.isEmpty {
                out[key] = TrackTileBucket(segments: kept)
            }
        }
        return out
    }

    private func merging(
        into base: [TrackTileKey: TrackTileBucket],
        with overlay: [TrackTileKey: TrackTileBucket]
    ) -> [TrackTileKey: TrackTileBucket] {
        var merged = base
        for (key, value) in overlay {
            var existing = merged[key]?.segments ?? []
            existing.append(contentsOf: value.segments)
            merged[key] = TrackTileBucket(segments: existing)
        }
        return merged
    }

    private func appendedEventsIfPossible(
        events: [TrackRenderEvent],
        previousCount: Int,
        previousLastTimestamp: Date?,
        previousLastCoord: CoordinateCodable?
    ) -> [TrackRenderEvent]? {
        guard previousCount >= 0 else { return nil }
        guard events.count >= previousCount else { return nil }
        if previousCount == 0 {
            return events
        }
        guard let previousLastTimestamp, let previousLastCoord else { return nil }
        let pivot = events[previousCount - 1]
        guard pivot.timestamp == previousLastTimestamp, pivot.coordinate == previousLastCoord else {
            return nil
        }
        if events.count == previousCount {
            return []
        }
        return Array(events.dropFirst(previousCount))
    }

    private func dayKeys(for segment: TrackTileSegment) -> [String] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: segment.startTimestamp)
        let endDay = cal.startOfDay(for: segment.endTimestamp)
        if startDay > endDay { return [dayKey(for: startDay)] }

        var out: [String] = []
        var cursor = startDay
        while cursor <= endDay {
            out.append(dayKey(for: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func dayKey(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Calendar.current.startOfDay(for: day))
    }

    private func sortKeys(_ lhs: TrackTileKey, _ rhs: TrackTileKey) -> Bool {
        if lhs.z != rhs.z { return lhs.z < rhs.z }
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }

    private func tileXRange(minLon: Double, maxLon: Double, z: Int) -> ClosedRange<Int> {
        let n = Double(1 << z)
        let lo = Int((((minLon + 180.0) / 360.0) * n).rounded(.down))
        let hi = Int((((maxLon + 180.0) / 360.0) * n).rounded(.down))
        let clampedLo = min(max(0, min(lo, hi)), Int(n) - 1)
        let clampedHi = min(max(0, max(lo, hi)), Int(n) - 1)
        return clampedLo...clampedHi
    }

    private func tileYRange(minLat: Double, maxLat: Double, z: Int) -> ClosedRange<Int> {
        func yTile(_ lat: Double, z: Int) -> Int {
            let safeLat = min(max(lat, -85.0511), 85.0511)
            let n = Double(1 << z)
            let latRad = safeLat * .pi / 180.0
            let yRaw = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n
            return Int(yRaw.rounded(.down))
        }

        let n = Int(1 << z)
        let lo = yTile(maxLat, z: z)
        let hi = yTile(minLat, z: z)
        let clampedLo = min(max(0, min(lo, hi)), n - 1)
        let clampedHi = min(max(0, max(lo, hi)), n - 1)
        return clampedLo...clampedHi
    }
}
