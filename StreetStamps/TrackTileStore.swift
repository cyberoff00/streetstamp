import Foundation
import CoreLocation
import Combine

final class TrackTileStore: ObservableObject {
    private static let currentSchemaVersion = 3
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
                var merged: [TrackTileKey: TrackTileBucket]
                var dayIndex: [String: [IndexedSegment]]

                if let manifest,
                   manifest.zoom == z,
                   manifest.schemaVersion == Self.currentSchemaVersion,
                   bucketsByZoom[z] != nil {
                    merged = bucketsByZoom[z] ?? [:]
                    dayIndex = dayIndexByZoom[z] ?? [:]

                    if manifest.journeyRevision != journeyRevision {
                        let appended = appendedEventsIfPossible(
                            events: journeyEvents,
                            previousCount: manifest.journeyEventCount,
                            previousLastTimestamp: manifest.journeyLastEventTimestamp,
                            previousLastCoord: manifest.journeyLastEventCoord
                        )
                        if let appended, !appended.isEmpty {
                            let overlay = TrackTileBuilder.build(events: appended, zoom: z).tiles
                            merged = merging(into: merged, with: overlay)
                            dayIndex = mergingDayIndex(base: dayIndex, overlayTiles: overlay)
                        } else {
                            merged = removing(source: .journey, from: merged)
                            let rebuiltJourney = TrackTileBuilder.build(events: journeyEvents, zoom: z).tiles
                            merged = merging(into: merged, with: rebuiltJourney)
                            dayIndex = buildDayIndex(for: merged)
                        }
                    }

                    if manifest.passiveRevision != passiveRevision {
                        let appended = appendedEventsIfPossible(
                            events: passiveEvents,
                            previousCount: manifest.passiveEventCount,
                            previousLastTimestamp: manifest.passiveLastEventTimestamp,
                            previousLastCoord: manifest.passiveLastEventCoord
                        )
                        if let appended, !appended.isEmpty {
                            let overlay = TrackTileBuilder.build(events: appended, zoom: z).tiles
                            merged = merging(into: merged, with: overlay)
                            dayIndex = mergingDayIndex(base: dayIndex, overlayTiles: overlay)
                        } else {
                            merged = removing(source: .passive, from: merged)
                            let rebuiltPassive = TrackTileBuilder.build(events: passiveEvents, zoom: z).tiles
                            merged = merging(into: merged, with: rebuiltPassive)
                            dayIndex = buildDayIndex(for: merged)
                        }
                    }
                } else {
                    let all = journeyEvents + passiveEvents
                    merged = TrackTileBuilder.build(events: all, zoom: z).tiles
                    dayIndex = buildDayIndex(for: merged)
                }

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
                    out.append(entry.segment)
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
                    if let sourceFilter {
                        out.append(contentsOf: bucket.segments.filter { sourceFilter.contains($0.sourceType) })
                    } else {
                        out.append(contentsOf: bucket.segments)
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

    private func removing(source: TrackSourceType, from input: [TrackTileKey: TrackTileBucket]) -> [TrackTileKey: TrackTileBucket] {
        var out: [TrackTileKey: TrackTileBucket] = [:]
        for (key, bucket) in input {
            let kept = bucket.segments.filter { $0.sourceType != source }
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

    private func mergingDayIndex(
        base: [String: [IndexedSegment]],
        overlayTiles: [TrackTileKey: TrackTileBucket]
    ) -> [String: [IndexedSegment]] {
        var out = base
        for (key, bucket) in overlayTiles {
            for segment in bucket.segments {
                for day in dayKeys(for: segment) {
                    out[day, default: []].append(IndexedSegment(key: key, segment: segment))
                }
            }
        }
        return out
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
