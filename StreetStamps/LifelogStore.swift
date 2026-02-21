import Foundation
import CoreLocation
import Combine
import MapKit

@MainActor
final class LifelogStore: ObservableObject {
    @Published private(set) var coordinates: [CoordinateCodable] = []
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var availableDays: [Date] = []

    private struct PersistedPayload: Codable {
        var points: [LifelogTrackPoint]?
        var coordinates: [CoordinateCodable]
        var isEnabled: Bool
        var archivedJourneyIDs: [String]?
        var moodByDay: [String: String]?
        var hasBackfilledHistoricalJourneys: Bool?
    }

    private struct LifelogTrackPoint: Codable {
        var lat: Double
        var lon: Double
        var timestamp: Date

        init(lat: Double, lon: Double, timestamp: Date) {
            self.lat = lat
            self.lon = lon
            self.timestamp = timestamp
        }

        init(_ coord: CoordinateCodable, timestamp: Date) {
            self.lat = coord.lat
            self.lon = coord.lon
            self.timestamp = timestamp
        }

        var coord: CoordinateCodable {
            CoordinateCodable(lat: lat, lon: lon)
        }
    }

    private let minDistanceMeters: CLLocationDistance = 25
    private let minIntervalSeconds: TimeInterval = 30

    private var persistURL: URL
    private var bag = Set<AnyCancellable>()
    private var lastAccepted: CLLocation?
    private var lastAcceptedAt: Date = .distantPast
    private var cachedDistanceMeters: Double = 0
    private var cachedGlobePolyline: [CoordinateCodable] = []
    private var cachedGlobePolylineSourceCount: Int = -1
    private var downsampleCache: [Int: [CoordinateCodable]] = [:]
    private var downsampleCacheSourceCount: Int = -1
    private var dayCoordsCache: [String: [CoordinateCodable]] = [:]
    private var dayDownsampleCache: [String: [Int: [CoordinateCodable]]] = [:]
    private var dayTileIndexCache: [String: [Int: [TileKey: [IndexedCoord]]]] = [:]
    private var dayTileIndexSourceCount: Int = -1
    private var previewPolylineCache: [String: [CLLocationCoordinate2D]] = [:]
    private var previewCacheSourceCount: Int = -1
    private var points: [LifelogTrackPoint] = []
    private var archivedJourneyIDs = Set<String>()
    private var moodByDay: [String: String] = [:]
    private var hasBackfilledHistoricalJourneys = false
    private let syntheticMaxPoints = 320

    private struct IndexedCoord {
        let idx: Int
        let coord: CoordinateCodable
    }

    private struct TileKey: Hashable {
        let z: Int
        let x: Int
        let y: Int
    }

    init(paths: StoragePath) {
        self.persistURL = paths.lifelogRouteURL
    }

    func rebind(paths: StoragePath) {
        persistURL = paths.lifelogRouteURL
        bag.removeAll()
        coordinates = []
        currentLocation = nil
        lastAccepted = nil
        lastAcceptedAt = .distantPast
        cachedDistanceMeters = 0
        cachedGlobePolyline = []
        cachedGlobePolylineSourceCount = -1
        downsampleCache = [:]
        downsampleCacheSourceCount = -1
        dayCoordsCache = [:]
        dayDownsampleCache = [:]
        dayTileIndexCache = [:]
        dayTileIndexSourceCount = -1
        previewPolylineCache = [:]
        previewCacheSourceCount = -1
        points = []
        archivedJourneyIDs = []
        moodByDay = [:]
        hasBackfilledHistoricalJourneys = false
        availableDays = []
    }

    func load() {
        guard
            let data = try? Data(contentsOf: persistURL),
            let payload = try? JSONDecoder().decode(PersistedPayload.self, from: data)
        else {
            points = []
            coordinates = []
            isEnabled = true
            cachedDistanceMeters = 0
            cachedGlobePolyline = []
            cachedGlobePolylineSourceCount = 0
            downsampleCache = [:]
            downsampleCacheSourceCount = 0
            dayCoordsCache = [:]
            dayDownsampleCache = [:]
            dayTileIndexCache = [:]
            dayTileIndexSourceCount = 0
            previewPolylineCache = [:]
            previewCacheSourceCount = 0
            archivedJourneyIDs = []
            moodByDay = [:]
            hasBackfilledHistoricalJourneys = false
            availableDays = []
            return
        }

        let loadedPoints: [LifelogTrackPoint]
        if let payloadPoints = payload.points, !payloadPoints.isEmpty {
            loadedPoints = payloadPoints
        } else {
            // Legacy fallback: old payload has only coordinates.
            let fallbackTS = Date()
            loadedPoints = payload.coordinates.map { LifelogTrackPoint($0, timestamp: fallbackTS) }
        }
        points = loadedPoints
        coordinates = loadedPoints.map(\.coord)
        isEnabled = payload.isEnabled
        archivedJourneyIDs = Set(payload.archivedJourneyIDs ?? [])
        moodByDay = payload.moodByDay ?? [:]
        hasBackfilledHistoricalJourneys = payload.hasBackfilledHistoricalJourneys ?? false
        cachedDistanceMeters = totalDistanceMeters(coords: coordinates)
        cachedGlobePolyline = []
        cachedGlobePolylineSourceCount = -1
        downsampleCache = [:]
        downsampleCacheSourceCount = -1
        dayCoordsCache = [:]
        dayDownsampleCache = [:]
        dayTileIndexCache = [:]
        dayTileIndexSourceCount = -1
        previewPolylineCache = [:]
        previewCacheSourceCount = -1
        refreshAvailableDays()

        if let last = coordinates.last {
            lastAccepted = CLLocation(latitude: last.lat, longitude: last.lon)
            lastAcceptedAt = Date()
        }
    }

    func bind(to hub: LocationHub) {
        bag.removeAll()
        hub.locationStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.ingest(loc)
            }
            .store(in: &bag)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        persistAsync()
    }

    var hasTrack: Bool { coordinates.count >= 2 }
    var totalDistanceMeters: Double { cachedDistanceMeters }

    var syntheticJourney: JourneyRoute {
        var route = JourneyRoute()
        route.id = "lifelog.route.synthetic"
        route.cityName = "Lifelog"
        route.currentCity = "Lifelog"
        route.canonicalCity = "Lifelog"
        route.cityKey = "Lifelog|"
        let polyline = globePolyline(maxPoints: syntheticMaxPoints)
        route.coordinates = polyline
        route.thumbnailCoordinates = polyline
        route.distance = cachedDistanceMeters
        return route
    }

    private func ingest(_ loc: CLLocation) {
        currentLocation = loc
        guard isEnabled else { return }
        // Journey in-progress owns point storage; Lifelog only stores passive points.
        if TrackingService.shared.isTracking { return }
        guard loc.horizontalAccuracy >= 0 else { return }

        if let last = lastAccepted {
            let moved = loc.distance(from: last)
            let dt = loc.timestamp.timeIntervalSince(lastAcceptedAt)
            if moved < minDistanceMeters && dt < minIntervalSeconds {
                return
            }
        }

        let c = CoordinateCodable(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        if let prev = coordinates.last,
           abs(prev.lat - c.lat) < 0.0000005,
           abs(prev.lon - c.lon) < 0.0000005 {
            return
        }

        if let prev = coordinates.last {
            let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
            let b = CLLocation(latitude: c.lat, longitude: c.lon)
            cachedDistanceMeters += b.distance(from: a)
        }

        coordinates.append(c)
        points.append(LifelogTrackPoint(c, timestamp: loc.timestamp))
        invalidatePolylineCaches()
        lastAccepted = loc
        lastAcceptedAt = loc.timestamp
        refreshAvailableDays()
        persistAsync()
    }

    func archiveJourneyPointsIfNeeded(_ journey: JourneyRoute) {
        _ = archiveJourneyPointsIfNeeded(journey, persistAfter: true)
    }

    @discardableResult
    private func archiveJourneyPointsIfNeeded(_ journey: JourneyRoute, persistAfter: Bool) -> Bool {
        let journeyID = journey.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !journeyID.isEmpty else { return false }
        guard !archivedJourneyIDs.contains(journeyID) else { return false }

        let coords = journey.coordinates
        guard !coords.isEmpty else {
            archivedJourneyIDs.insert(journeyID)
            if persistAfter {
                persistAsync()
            }
            return true
        }

        let timeline = timestampsForJourney(journey, count: coords.count)
        for (idx, coord) in coords.enumerated() {
            let point = LifelogTrackPoint(coord, timestamp: timeline[idx])
            points.append(point)
            coordinates.append(point.coord)
        }

        cachedDistanceMeters = totalDistanceMeters(coords: coordinates)
        invalidatePolylineCaches()
        archivedJourneyIDs.insert(journeyID)
        refreshAvailableDays()
        if persistAfter {
            persistAsync()
        }
        return true
    }

    func importExternalTrack(points imported: [(coord: CoordinateCodable, timestamp: Date)]) {
        guard !imported.isEmpty else { return }

        for item in imported {
            let coord = item.coord
            let timestamp = item.timestamp

            if let prev = coordinates.last,
               abs(prev.lat - coord.lat) < 0.0000005,
               abs(prev.lon - coord.lon) < 0.0000005 {
                continue
            }

            if let prev = coordinates.last {
                let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
                let b = CLLocation(latitude: coord.lat, longitude: coord.lon)
                cachedDistanceMeters += b.distance(from: a)
            }

            coordinates.append(coord)
            points.append(LifelogTrackPoint(coord, timestamp: timestamp))
        }

        invalidatePolylineCaches()
        refreshAvailableDays()
        persistAsync()
    }

    func backfillHistoricalJourneysIfNeeded(from journeys: [JourneyRoute]) async {
        guard !hasBackfilledHistoricalJourneys else { return }

        let completed = journeys
            .filter { $0.endTime != nil }
            .sorted { lhs, rhs in
                let lStart = lhs.startTime ?? lhs.endTime ?? .distantPast
                let rStart = rhs.startTime ?? rhs.endTime ?? .distantPast
                if lStart != rStart { return lStart < rStart }
                let lEnd = lhs.endTime ?? lhs.startTime ?? .distantPast
                let rEnd = rhs.endTime ?? rhs.startTime ?? .distantPast
                if lEnd != rEnd { return lEnd < rEnd }
                return lhs.id < rhs.id
            }

        var processed = 0
        for journey in completed {
            if Task.isCancelled { return }
            _ = archiveJourneyPointsIfNeeded(journey, persistAfter: false)
            processed += 1
            if processed % 12 == 0 {
                await Task.yield()
            }
        }

        hasBackfilledHistoricalJourneys = true
        persistAsync()
    }

    func mapPolylinePreview(
        day: Date?,
        center: CLLocationCoordinate2D?,
        radiusMeters: CLLocationDistance = 1500,
        recentCount: Int = 420,
        maxPoints: Int = 420
    ) -> [CLLocationCoordinate2D] {
        if previewCacheSourceCount != coordinates.count {
            previewPolylineCache.removeAll(keepingCapacity: true)
            previewCacheSourceCount = coordinates.count
        }

        let cacheKey = makePreviewCacheKey(
            day: day,
            center: center,
            radiusMeters: radiusMeters,
            recentCount: recentCount,
            maxPoints: maxPoints
        )
        if let cached = previewPolylineCache[cacheKey] {
            return cached
        }

        let dayCoords = coordsFor(day: day)
        guard !dayCoords.isEmpty else {
            previewPolylineCache[cacheKey] = []
            return []
        }

        let tail = Array(dayCoords.suffix(max(2, recentCount)))
        var mixed = tail

        if let center, center.isValid {
            let c = CLLocation(latitude: center.latitude, longitude: center.longitude)
            for coord in dayCoords {
                let p = CLLocation(latitude: coord.lat, longitude: coord.lon)
                if p.distance(from: c) <= radiusMeters {
                    mixed.append(coord)
                }
            }
        }

        if mixed.count <= 2 {
            mixed = tail
        }

        var deduped: [CoordinateCodable] = []
        deduped.reserveCapacity(mixed.count)
        for coord in mixed {
            if let last = deduped.last, last.lat == coord.lat, last.lon == coord.lon {
                continue
            }
            deduped.append(coord)
        }

        let result = downsample(coords: deduped, maxPoints: max(maxPoints, 2)).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        previewPolylineCache[cacheKey] = result
        return result
    }

    func sampledCoordinates(maxPoints: Int) -> [CoordinateCodable] {
        sampledCoordinates(day: nil, maxPoints: maxPoints)
    }

    func mood(for day: Date) -> String? {
        moodByDay[dayKey(day)]
    }

    func setMood(_ mood: String?, for day: Date) {
        let key = dayKey(day)
        if let mood, !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            moodByDay[key] = mood
        } else {
            moodByDay.removeValue(forKey: key)
        }
        persistAsync()
    }

    func sampledCoordinates(day: Date?, maxPoints: Int) -> [CoordinateCodable] {
        if day != nil {
            let target = max(maxPoints, 2)
            let key = dayKey(day!)
            if let cached = dayDownsampleCache[key]?[target] {
                return cached
            }
            let sampled = downsample(coords: coordsFor(day: day), maxPoints: target)
            var bucket = dayDownsampleCache[key] ?? [:]
            bucket[target] = sampled
            dayDownsampleCache[key] = bucket
            return sampled
        }
        let target = max(maxPoints, 2)
        if downsampleCacheSourceCount != coordinates.count {
            downsampleCache.removeAll(keepingCapacity: true)
            downsampleCacheSourceCount = coordinates.count
        }
        if let cached = downsampleCache[target] {
            return cached
        }
        let sampled = downsample(coords: coordinates, maxPoints: target)
        downsampleCache[target] = sampled
        return sampled
    }

    func mapPolyline(maxPoints: Int) -> [CLLocationCoordinate2D] {
        mapPolyline(day: nil, maxPoints: maxPoints)
    }

    func mapPolyline(day: Date?, maxPoints: Int) -> [CLLocationCoordinate2D] {
        sampledCoordinates(day: day, maxPoints: maxPoints).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
    }

    func mapPolylineViewport(
        day: Date?,
        region: MKCoordinateRegion?,
        lodLevel: Int,
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard let region else {
            return mapPolyline(day: day, maxPoints: maxPoints)
        }

        let (tileZoom, stride) = lodSpec(for: lodLevel)
        let expanded = expand(region: region, factor: 1.35)
        guard let xRange = tileXRange(for: expanded, z: tileZoom),
              let yRange = tileYRange(for: expanded, z: tileZoom) else {
            return mapPolyline(day: day, maxPoints: maxPoints)
        }

        let index = tileIndex(for: day, stride: stride, z: tileZoom)
        guard !index.isEmpty else { return [] }

        var byIdx: [Int: CoordinateCodable] = [:]
        for x in xRange {
            for y in yRange {
                let key = TileKey(z: tileZoom, x: x, y: y)
                guard let entries = index[key] else { continue }
                for entry in entries {
                    byIdx[entry.idx] = entry.coord
                }
            }
        }

        if byIdx.isEmpty {
            return mapPolyline(day: day, maxPoints: max(maxPoints / 2, 120))
        }

        let ordered = byIdx.keys.sorted().compactMap { byIdx[$0] }
        let sampled = downsample(coords: ordered, maxPoints: max(maxPoints, 2))
        return sampled.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    private func persistAsync() {
        let payload = PersistedPayload(
            points: points,
            coordinates: coordinates,
            isEnabled: isEnabled,
            archivedJourneyIDs: Array(archivedJourneyIDs),
            moodByDay: moodByDay,
            hasBackfilledHistoricalJourneys: hasBackfilledHistoricalJourneys
        )
        let url = persistURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(payload)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                print("❌ lifelog save failed:", error)
            }
        }
    }

    private func totalDistanceMeters(coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].lat, longitude: coords[i - 1].lon)
            let b = CLLocation(latitude: coords[i].lat, longitude: coords[i].lon)
            total += b.distance(from: a)
        }
        return total
    }

    private func globePolyline(maxPoints: Int) -> [CoordinateCodable] {
        guard maxPoints >= 2 else { return coordinates }
        if cachedGlobePolylineSourceCount == coordinates.count {
            return cachedGlobePolyline
        }

        let sampled = downsample(coords: coordinates, maxPoints: maxPoints)
        cachedGlobePolyline = sampled
        cachedGlobePolylineSourceCount = coordinates.count
        return sampled
    }

    func globeJourneys(
        maxPointsPerSegment: Int = 280,
        splitDistanceMeters: CLLocationDistance = 25_000,
        splitTimeGapSeconds: TimeInterval = 2 * 60 * 60
    ) -> [JourneyRoute] {
        guard points.count >= 2 else {
            if hasTrack { return [syntheticJourney] }
            return []
        }

        var groups: [[LifelogTrackPoint]] = []
        var current: [LifelogTrackPoint] = [points[0]]

        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let now = points[idx]

            let dt = now.timestamp.timeIntervalSince(prev.timestamp)
            let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
            let b = CLLocation(latitude: now.lat, longitude: now.lon)
            let d = b.distance(from: a)

            if dt > splitTimeGapSeconds || d > splitDistanceMeters {
                if current.count >= 2 {
                    groups.append(current)
                }
                current = [now]
            } else {
                current.append(now)
            }
        }

        if current.count >= 2 {
            groups.append(current)
        }

        if groups.isEmpty {
            return [syntheticJourney]
        }

        var out: [JourneyRoute] = []
        out.reserveCapacity(groups.count)

        for (index, segment) in groups.enumerated() {
            let coords = segment.map { CoordinateCodable(lat: $0.lat, lon: $0.lon) }
            let sampled = downsample(coords: coords, maxPoints: max(2, maxPointsPerSegment))
            guard sampled.count >= 2 else { continue }

            var route = JourneyRoute()
            let startTS = segment.first?.timestamp ?? .distantPast
            let endTS = segment.last?.timestamp ?? startTS
            route.id = "lifelog.globe.segment.\(index).\(Int(startTS.timeIntervalSince1970))"
            route.startTime = startTS
            route.endTime = endTS
            route.cityName = "Lifelog"
            route.currentCity = "Lifelog"
            route.canonicalCity = "Lifelog"
            route.cityKey = "Lifelog|"
            route.coordinates = sampled
            route.thumbnailCoordinates = sampled
            route.distance = totalDistanceMeters(coords: sampled)
            out.append(route)
        }

        return out
    }

    private func coordsFor(day: Date?) -> [CoordinateCodable] {
        guard let day else { return coordinates }
        let key = dayKey(day)
        if let cached = dayCoordsCache[key] {
            return cached
        }
        let cal = Calendar.current
        let out = points
            .filter { cal.isDate($0.timestamp, inSameDayAs: day) }
            .map(\.coord)
        dayCoordsCache[key] = out
        return out
    }

    private func refreshAvailableDays() {
        let cal = Calendar.current
        let uniq = Set(points.map { cal.startOfDay(for: $0.timestamp) })
        availableDays = uniq.sorted(by: >)
    }

    private func timestampsForJourney(_ journey: JourneyRoute, count: Int) -> [Date] {
        let end = journey.endTime ?? Date()
        let start = journey.startTime ?? end
        if count <= 1 { return [end] }

        let span = max(0, end.timeIntervalSince(start))
        if span <= 0 {
            return (0..<count).map { _ in end }
        }

        return (0..<count).map { idx in
            let t = Double(idx) / Double(max(count - 1, 1))
            return start.addingTimeInterval(span * t)
        }
    }

    private func dayKey(_ day: Date) -> String {
        let start = Calendar.current.startOfDay(for: day)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: start)
    }

    private func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints else { return coords }

        let n = coords.count
        var out: [CoordinateCodable] = []
        out.reserveCapacity(maxPoints)

        for i in 0..<maxPoints {
            let t = Double(i) / Double(maxPoints - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }

        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(out.count)
        for c in out {
            if let last = compact.last, last.lat == c.lat, last.lon == c.lon {
                continue
            }
            compact.append(c)
        }
        return compact
    }

    private func invalidatePolylineCaches() {
        cachedGlobePolylineSourceCount = -1
        downsampleCacheSourceCount = -1
        dayCoordsCache.removeAll(keepingCapacity: true)
        dayDownsampleCache.removeAll(keepingCapacity: true)
        dayTileIndexSourceCount = -1
        dayTileIndexCache.removeAll(keepingCapacity: true)
        previewCacheSourceCount = -1
        previewPolylineCache.removeAll(keepingCapacity: true)
    }

    private func makePreviewCacheKey(
        day: Date?,
        center: CLLocationCoordinate2D?,
        radiusMeters: CLLocationDistance,
        recentCount: Int,
        maxPoints: Int
    ) -> String {
        let dayPart = day.map(dayKey) ?? "all"
        let radiusPart = Int(radiusMeters.rounded())
        let centerPart: String
        if let center, center.isValid {
            let step = 0.02
            let qLat = (center.latitude / step).rounded() * step
            let qLon = (center.longitude / step).rounded() * step
            centerPart = "\(qLat),\(qLon)"
        } else {
            centerPart = "nil"
        }
        return "\(dayPart)|\(centerPart)|\(radiusPart)|\(recentCount)|\(maxPoints)"
    }

    private func tileIndex(for day: Date?, stride sampleStride: Int, z: Int) -> [TileKey: [IndexedCoord]] {
        if dayTileIndexSourceCount != coordinates.count {
            dayTileIndexCache.removeAll(keepingCapacity: true)
            dayTileIndexSourceCount = coordinates.count
        }

        let dayPart = day.map(dayKey) ?? "all"
        if let cached = dayTileIndexCache[dayPart]?[sampleStride] {
            return cached
        }

        let src = coordsFor(day: day)
        var out: [TileKey: [IndexedCoord]] = [:]
        if src.isEmpty { return out }

        var idx = 0
        for i in Swift.stride(from: 0, to: src.count, by: max(1, sampleStride)) {
            let coord = src[i]
            if let key = tileKey(for: coord, z: z) {
                out[key, default: []].append(IndexedCoord(idx: idx, coord: coord))
            }
            idx += 1
        }

        var lodBucket = dayTileIndexCache[dayPart] ?? [:]
        lodBucket[sampleStride] = out
        dayTileIndexCache[dayPart] = lodBucket
        return out
    }

    private func lodSpec(for level: Int) -> (tileZoom: Int, stride: Int) {
        switch max(0, min(level, 3)) {
        case 0: return (8, 14)
        case 1: return (10, 8)
        case 2: return (12, 4)
        default: return (14, 1)
        }
    }

    private func expand(region: MKCoordinateRegion, factor: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.0008, region.span.latitudeDelta * factor),
                longitudeDelta: max(0.0008, region.span.longitudeDelta * factor)
            )
        )
    }

    private func tileKey(for coord: CoordinateCodable, z: Int) -> TileKey? {
        guard coord.lat >= -85.0511, coord.lat <= 85.0511 else { return nil }
        let n = Double(1 << z)
        let x = Int(((coord.lon + 180.0) / 360.0 * n).rounded(.down))
        let latRad = coord.lat * .pi / 180.0
        let yRaw = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n
        let y = Int(yRaw.rounded(.down))
        let clampX = min(max(0, x), Int(n) - 1)
        let clampY = min(max(0, y), Int(n) - 1)
        return TileKey(z: z, x: clampX, y: clampY)
    }

    private func tileXRange(for region: MKCoordinateRegion, z: Int) -> ClosedRange<Int>? {
        let n = Double(1 << z)
        let minLon = region.center.longitude - region.span.longitudeDelta / 2.0
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2.0
        let minX = Int((((minLon + 180.0) / 360.0) * n).rounded(.down))
        let maxX = Int((((maxLon + 180.0) / 360.0) * n).rounded(.down))
        let clampedMin = min(max(0, minX), Int(n) - 1)
        let clampedMax = min(max(0, maxX), Int(n) - 1)
        if clampedMin <= clampedMax {
            return clampedMin...clampedMax
        }
        return nil
    }

    private func tileYRange(for region: MKCoordinateRegion, z: Int) -> ClosedRange<Int>? {
        func tileY(_ lat: Double, z: Int) -> Int {
            let safeLat = min(max(lat, -85.0511), 85.0511)
            let n = Double(1 << z)
            let latRad = safeLat * .pi / 180.0
            let yRaw = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n
            return Int(yRaw.rounded(.down))
        }
        let n = Int(1 << z)
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2.0
        let minLat = region.center.latitude - region.span.latitudeDelta / 2.0
        let top = min(max(0, tileY(maxLat, z: z)), n - 1)
        let bottom = min(max(0, tileY(minLat, z: z)), n - 1)
        let lo = min(top, bottom)
        let hi = max(top, bottom)
        return lo...hi
    }
}
