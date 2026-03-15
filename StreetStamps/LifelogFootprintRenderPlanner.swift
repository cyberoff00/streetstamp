import Foundation
import CoreLocation
import MapKit

struct LifelogFootprintProjectedMarker: Equatable {
    let coordinate: CLLocationCoordinate2D
    let angleDegrees: Double
}

final class LifelogFootprintViewportCache {
    struct Key: Hashable {
        let lodLevel: Int
        let minLatE4: Int
        let maxLatE4: Int
        let minLonE4: Int
        let maxLonE4: Int
        let runsSignature: Int
        let exclusionLatE4: Int?
        let exclusionLonE4: Int?

        init(
            lodLevel: Int,
            region: MKCoordinateRegion,
            runsSignature: Int,
            exclusionCoordinate: CLLocationCoordinate2D?
        ) {
            self.lodLevel = lodLevel
            self.minLatE4 = Self.quantize(region.center.latitude - (region.span.latitudeDelta / 2.0))
            self.maxLatE4 = Self.quantize(region.center.latitude + (region.span.latitudeDelta / 2.0))
            self.minLonE4 = Self.quantize(region.center.longitude - (region.span.longitudeDelta / 2.0))
            self.maxLonE4 = Self.quantize(region.center.longitude + (region.span.longitudeDelta / 2.0))
            self.runsSignature = runsSignature
            self.exclusionLatE4 = exclusionCoordinate.map { Self.quantize($0.latitude) }
            self.exclusionLonE4 = exclusionCoordinate.map { Self.quantize($0.longitude) }
        }

        private static func quantize(_ value: Double) -> Int {
            Int((value * 10_000).rounded())
        }
    }

    private let limit: Int
    private var storage: [Key: [LifelogFootprintProjectedMarker]] = [:]
    private var lru: [Key] = []

    init(limit: Int = 24) {
        self.limit = max(1, limit)
    }

    func value(
        for key: Key,
        builder: () -> [LifelogFootprintProjectedMarker]
    ) -> [LifelogFootprintProjectedMarker] {
        if let cached = storage[key] {
            touch(key)
            return cached
        }

        let built = builder()
        storage[key] = built
        touch(key)
        trimIfNeeded()
        return built
    }

    func removeAll() {
        storage.removeAll(keepingCapacity: true)
        lru.removeAll(keepingCapacity: true)
    }

    private func touch(_ key: Key) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func trimIfNeeded() {
        while lru.count > limit {
            let removed = lru.removeFirst()
            storage.removeValue(forKey: removed)
        }
    }
}

enum LifelogFootprintRenderPlanner {
    private struct Settings {
        let maxMarkers: Int
        let minSeparationMeters: CLLocationDistance
        let gridCellRatio: Double
        let exclusionMeters: CLLocationDistance
        let viewportBufferRatio: Double
    }

    static func runsSignature(_ runs: [[CLLocationCoordinate2D]]) -> Int {
        var hasher = Hasher()
        hasher.combine(runs.count)
        for run in runs {
            hasher.combine(run.count)
            if let first = run.first {
                hasher.combine(first.latitude.bitPattern)
                hasher.combine(first.longitude.bitPattern)
            }
            if let last = run.last {
                hasher.combine(last.latitude.bitPattern)
                hasher.combine(last.longitude.bitPattern)
            }
        }
        return hasher.finalize()
    }

    static func plannedMarkers(
        from runs: [[CLLocationCoordinate2D]],
        region: MKCoordinateRegion,
        lodLevel: Int,
        currentCoordinate: CLLocationCoordinate2D?
    ) -> [LifelogFootprintProjectedMarker] {
        let settings = settings(for: lodLevel)
        var markers: [LifelogFootprintProjectedMarker] = []

        for run in runs {
            let clipped = clippedSubruns(
                from: run,
                in: region,
                bufferRatio: settings.viewportBufferRatio
            )
            let filtered = clipped.compactMap { subrun in
                filteredSubrun(subrun, excluding: currentCoordinate, radiusMeters: settings.exclusionMeters)
            }
            for subrun in filtered {
                let decimatedRun = decimated(subrun, region: region, settings: settings)
                for (index, coord) in decimatedRun.enumerated() {
                    guard isInsideBufferedViewport(coord, region: region, bufferRatio: settings.viewportBufferRatio) else {
                        continue
                    }
                    markers.append(
                        LifelogFootprintProjectedMarker(
                            coordinate: coord,
                            angleDegrees: headingDegrees(at: index, in: decimatedRun)
                        )
                    )
                }
            }
        }
        return markers
    }

    private static func settings(for lodLevel: Int) -> Settings {
        switch lodLevel {
        case 3:
            return Settings(
                maxMarkers: 140,
                minSeparationMeters: 24,
                gridCellRatio: 0.020,
                exclusionMeters: 26,
                viewportBufferRatio: 0.12
            )
        case 2:
            return Settings(
                maxMarkers: 92,
                minSeparationMeters: 36,
                gridCellRatio: 0.036,
                exclusionMeters: 34,
                viewportBufferRatio: 0.14
            )
        case 1:
            return Settings(
                maxMarkers: 56,
                minSeparationMeters: 52,
                gridCellRatio: 0.056,
                exclusionMeters: 44,
                viewportBufferRatio: 0.16
            )
        default:
            return Settings(
                maxMarkers: 34,
                minSeparationMeters: 56,
                gridCellRatio: 0.090,
                exclusionMeters: 56,
                viewportBufferRatio: 0.18
            )
        }
    }

    private static func clippedSubruns(
        from run: [CLLocationCoordinate2D],
        in region: MKCoordinateRegion,
        bufferRatio: Double
    ) -> [[CLLocationCoordinate2D]] {
        guard !run.isEmpty else { return [] }

        var clipped: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []

        for index in run.indices {
            let coord = run[index]
            let isVisible = isInsideBufferedViewport(coord, region: region, bufferRatio: bufferRatio)

            if isVisible {
                if current.isEmpty, index > 0 {
                    current.append(run[index - 1])
                }
                current.append(coord)
                continue
            }

            if !current.isEmpty {
                current.append(coord)
                clipped.append(deduplicated(current))
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            clipped.append(deduplicated(current))
        }

        return clipped.filter { $0.count >= 2 }
    }

    private static func filteredSubrun(
        _ run: [CLLocationCoordinate2D],
        excluding currentCoordinate: CLLocationCoordinate2D?,
        radiusMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D]? {
        guard let currentCoordinate, radiusMeters > 0 else {
            return run.count >= 2 ? run : nil
        }

        let me = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let filtered = run.filter { coord in
            let point = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return point.distance(from: me) > radiusMeters
        }
        return filtered.count >= 2 ? filtered : nil
    }

    private static func decimated(
        _ coords: [CLLocationCoordinate2D],
        region: MKCoordinateRegion,
        settings: Settings
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 3 else { return coords }

        let maxMarkers = max(2, min(settings.maxMarkers, coords.count))
        let cell = max(0.010, settings.gridCellRatio)

        var selected = Set<Int>()
        selected.insert(0)
        selected.insert(coords.count - 1)

        func cellKey(for index: Int) -> String? {
            guard let p = normalizedViewportPoint(coords[index], in: region) else { return nil }
            guard p.x >= -0.2, p.x <= 1.2, p.y >= -0.2, p.y <= 1.2 else { return nil }
            let cx = Int(floor(p.x / cell))
            let cy = Int(floor(p.y / cell))
            return "\(cx)|\(cy)"
        }

        func localSpacingMeters(at index: Int) -> CLLocationDistance {
            guard index > 0, index < coords.count - 1 else { return .greatestFiniteMagnitude }
            let prev = CLLocation(latitude: coords[index - 1].latitude, longitude: coords[index - 1].longitude)
            let cur = CLLocation(latitude: coords[index].latitude, longitude: coords[index].longitude)
            let next = CLLocation(latitude: coords[index + 1].latitude, longitude: coords[index + 1].longitude)
            return max(cur.distance(from: prev), next.distance(from: cur))
        }

        func isFarEnough(_ index: Int, from picked: Set<Int>) -> Bool {
            let minSeparation = settings.minSeparationMeters
            guard minSeparation > 0 else { return true }
            let candidate = CLLocation(latitude: coords[index].latitude, longitude: coords[index].longitude)
            for pickedIndex in picked {
                let pickedLocation = CLLocation(
                    latitude: coords[pickedIndex].latitude,
                    longitude: coords[pickedIndex].longitude
                )
                if candidate.distance(from: pickedLocation) < minSeparation {
                    return false
                }
            }
            return true
        }

        for index in 1..<(coords.count - 1) {
            if isFarEnough(index, from: selected) {
                selected.insert(index)
            }
        }

        if selected.count > maxMarkers {
            let ranked = selected.sorted { localSpacingMeters(at: $0) > localSpacingMeters(at: $1) }
            selected = Set(ranked.prefix(maxMarkers))
            selected.insert(0)
            selected.insert(coords.count - 1)
        }

        var occupied = Set<String>()
        for index in selected {
            if let key = cellKey(for: index) {
                occupied.insert(key)
            }
        }

        if selected.count < maxMarkers {
            for index in 0..<coords.count {
                if selected.contains(index) { continue }
                if !isFarEnough(index, from: selected) { continue }
                guard let key = cellKey(for: index) else { continue }
                if occupied.contains(key) { continue }
                selected.insert(index)
                occupied.insert(key)
                if selected.count >= maxMarkers { break }
            }
        }

        if selected.count < maxMarkers {
            let candidates = (0..<coords.count)
                .filter { !selected.contains($0) }
                .sorted { localSpacingMeters(at: $0) > localSpacingMeters(at: $1) }
            for index in candidates {
                if !isFarEnough(index, from: selected) { continue }
                selected.insert(index)
                if selected.count >= maxMarkers { break }
            }
        }

        return selected.sorted().map { coords[$0] }
    }

    private static func deduplicated(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coords.count)
        for coord in coords where !sameCoordinate(result.last, coord) {
            result.append(coord)
        }
        return result
    }

    private static func isInsideBufferedViewport(
        _ coord: CLLocationCoordinate2D,
        region: MKCoordinateRegion,
        bufferRatio: Double
    ) -> Bool {
        guard let point = normalizedViewportPoint(coord, in: region) else { return false }
        return point.x >= -bufferRatio &&
               point.x <= 1.0 + bufferRatio &&
               point.y >= -bufferRatio &&
               point.y <= 1.0 + bufferRatio
    }

    private static func normalizedViewportPoint(
        _ coord: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> CGPoint? {
        let latDelta = max(region.span.latitudeDelta, 0.000_001)
        let lonDelta = max(region.span.longitudeDelta, 0.000_001)
        let minLon = region.center.longitude - lonDelta / 2.0
        let maxLat = region.center.latitude + latDelta / 2.0

        let xRatio = (coord.longitude - minLon) / lonDelta
        let yRatio = (maxLat - coord.latitude) / latDelta
        guard xRatio.isFinite, yRatio.isFinite else { return nil }
        return CGPoint(x: xRatio, y: yRatio)
    }

    private static func headingDegrees(
        at index: Int,
        in coords: [CLLocationCoordinate2D]
    ) -> Double {
        guard coords.count >= 2 else { return -18 }
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        if index <= 0 {
            from = coords[0]
            to = coords[1]
        } else {
            from = coords[min(index - 1, coords.count - 1)]
            to = coords[min(index, coords.count - 1)]
        }
        return bearingDegrees(from: from, to: to)
    }

    private static func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let raw = atan2(y, x) * 180 / .pi
        return raw.isFinite ? raw : -18
    }

    private static func sameCoordinate(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 0.000_000_1 &&
               abs(a.longitude - b.longitude) < 0.000_000_1
    }
}
