import Foundation
import CoreLocation
import Combine
import MapKit

extension Notification.Name {
    static let lifelogStoreTrackTilesDidChange = Notification.Name("lifelogStoreTrackTilesDidChange")
}

@MainActor
final class LifelogStore: ObservableObject {
    enum ExternalTrackImportSource {
        case passiveRecovery
        case archive
    }

    private(set) var coordinates: [CoordinateCodable] = []
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var availableDays: [Date] = []
    @Published private(set) var countryISO2: String? = nil
    @Published private(set) var trackTileRevision: Int = 0
    @Published private(set) var hasLoaded: Bool = false

    private struct PersistedPayload: Codable {
        var points: [LifelogTrackPoint]?
        var coordinates: [CoordinateCodable]
        var isEnabled: Bool
        var archivedJourneyIDs: [String]?
        var moodByDay: [String: String]?
        var cachedDistanceMeters: Double?
        var cachedAvailableDays: [Date]?
    }

    struct LifelogTrackPoint: Codable {
        var id: String
        var lat: Double
        var lon: Double
        var timestamp: Date
        var accuracy: Double?
        var cellID: String

        init(
            id: String = UUID().uuidString,
            lat: Double,
            lon: Double,
            timestamp: Date,
            accuracy: Double? = nil,
            cellID: String? = nil
        ) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.timestamp = timestamp
            self.accuracy = accuracy
            self.cellID = cellID ?? TrackPointCellID.make(lat: lat, lon: lon)
        }

        init(_ coord: CoordinateCodable, timestamp: Date, accuracy: Double? = nil) {
            self.init(
                lat: coord.lat,
                lon: coord.lon,
                timestamp: timestamp,
                accuracy: accuracy,
                cellID: TrackPointCellID.make(for: coord)
            )
        }

        var coord: CoordinateCodable {
            CoordinateCodable(lat: lat, lon: lon)
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case lat
            case lon
            case timestamp
            case accuracy
            case cellID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            lat = try container.decode(Double.self, forKey: .lat)
            lon = try container.decode(Double.self, forKey: .lon)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)
            cellID = try container.decodeIfPresent(String.self, forKey: .cellID)
                ?? TrackPointCellID.make(lat: lat, lon: lon)
        }
    }

    private struct LoadedState {
        let points: [LifelogTrackPoint]
        let coordinates: [CoordinateCodable]
        let isEnabled: Bool
        let archivedJourneyIDs: Set<String>
        let moodByDay: [String: String]
        let cachedDistanceMeters: Double
        let availableDays: [Date]
        let countryISO2: String?
    }

    // Keep passive lifelog dense enough for continuous fog-of-world coverage.
    private let minDistanceMeters: CLLocationDistance = 10
    private let maxAcceptedHorizontalAccuracyStationary: CLLocationAccuracy = 65
    private let maxAcceptedHorizontalAccuracyMoving: CLLocationAccuracy = 95
    private let longGapFallbackInterval: TimeInterval = 90
    private let longGapFallbackDistanceMeters: CLLocationDistance = 120
    private let longGapFallbackMaxAccuracy: CLLocationAccuracy = 120
    private let stationaryEnterWindow: TimeInterval = 240
    private let stationaryClusterRadiusMeters: CLLocationDistance = 15
    private let stationaryExitDistanceMeters: CLLocationDistance = 30
    private let stationaryExitSpeedMetersPerSecond: CLLocationSpeed = 1.2
    private let motionHub = MotionActivityHub.shared

    private var userID: String
    private var persistURL: URL
    private var deltaURL: URL
    private var moodPersistURL: URL
    private var bag = Set<AnyCancellable>()
    private var lastAccepted: CLLocation?
    private var cachedDistanceMeters: Double = 0
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
    private var availableDayKeys = Set<String>()
    private var dirtyPointDayKeys = Set<String>()
    private var dirtyMoodDayKeys = Set<String>()
    private var deletedMoodDayKeys = Set<String>()
    private var pendingSnapshotPersist: DispatchWorkItem?
    private let snapshotPersistDebounce: TimeInterval = 4.0
    private let fileIOQueue = DispatchQueue(label: "com.streetstamps.lifelog.fileIO", qos: .utility)
    private var pendingTrackTileRevisionBump: DispatchWorkItem?
    private let trackTileRevisionDebounce: TimeInterval
    private var pendingDayIndexBuild: DispatchWorkItem?
    private var dayIndexBuildGeneration: Int = 0
    private var pendingBindHub: LocationHub?
    private var passiveMotionState: PassiveMotionState = .moving
    private var passiveMotionAnchor: CLLocation?
    private var passiveMotionAnchorTimestamp: Date = .distantPast
    private let attributionCoordinatorFactory: (StoragePath) -> LifelogCountryAttributionCoordinator
    private var attributionCoordinator: LifelogCountryAttributionCoordinator

    private struct IndexedCoord {
        let idx: Int
        let coord: CoordinateCodable
    }

    private enum PassiveMotionState {
        case moving
        case stationary
    }

    private struct TileKey: Hashable {
        let z: Int
        let x: Int
        let y: Int
    }

    init(
        paths: StoragePath,
        trackTileRevisionDebounce: TimeInterval = 1.5,
        attributionCoordinatorFactory: @escaping (StoragePath) -> LifelogCountryAttributionCoordinator = {
            LifelogCountryAttributionCoordinator(paths: $0)
        }
    ) {
        self.userID = paths.userID
        self.persistURL = paths.lifelogRouteURL
        self.deltaURL = paths.lifelogRouteURL
            .deletingPathExtension()
            .appendingPathExtension("delta.jsonl")
        self.moodPersistURL = paths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        self.trackTileRevisionDebounce = max(0, trackTileRevisionDebounce)
        self.attributionCoordinatorFactory = attributionCoordinatorFactory
        self.attributionCoordinator = attributionCoordinatorFactory(paths)
    }

    func rebind(paths: StoragePath) {
        userID = paths.userID
        persistURL = paths.lifelogRouteURL
        deltaURL = paths.lifelogRouteURL
            .deletingPathExtension()
            .appendingPathExtension("delta.jsonl")
        moodPersistURL = paths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        pendingSnapshotPersist?.cancel()
        pendingSnapshotPersist = nil
        pendingTrackTileRevisionBump?.cancel()
        pendingTrackTileRevisionBump = nil
        pendingDayIndexBuild?.cancel()
        pendingDayIndexBuild = nil
        bag.removeAll()
        pendingBindHub = nil
        resetPassiveMotionState()
        coordinates = []
        currentLocation = nil
        lastAccepted = nil
        cachedDistanceMeters = 0
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
        availableDayKeys = []
        dirtyPointDayKeys = []
        dirtyMoodDayKeys = []
        deletedMoodDayKeys = []
        availableDays = []
        countryISO2 = nil
        trackTileRevision = 0
        hasLoaded = false
        attributionCoordinator = attributionCoordinatorFactory(paths)
        bumpTrackTileRevision()
    }

    func load() {
        Task {
            await loadAsync()
        }
    }

    func loadAsync() async {
        hasLoaded = false
        let url = persistURL
        let delta = deltaURL
        let moodURL = moodPersistURL
        let loaded = await Self.loadState(from: url, deltaURL: delta, moodURL: moodURL)
        applyLoadedState(loaded)
        dirtyPointDayKeys = []
        dirtyMoodDayKeys = []
        deletedMoodDayKeys = []
        scheduleBackgroundDayIndexBuild()
        hasLoaded = true
        if let hub = pendingBindHub {
            activateBindings(to: hub)
        }
        bumpTrackTileRevision()
    }

    private func applyLoadedState(_ loaded: LoadedState) {
        points = loaded.points
        coordinates = loaded.points.map(\.coord)
        if AppSettings.hasPassiveLifelogPreference {
            isEnabled = AppSettings.isPassiveLifelogEnabled
        } else {
            isEnabled = loaded.isEnabled
            AppSettings.setPassiveLifelogEnabled(loaded.isEnabled)
        }
        archivedJourneyIDs = loaded.archivedJourneyIDs
        moodByDay = loaded.moodByDay
        cachedDistanceMeters = loaded.cachedDistanceMeters
        resetPassiveMotionState()
        downsampleCache = [:]
        downsampleCacheSourceCount = -1
        dayCoordsCache = [:]
        dayDownsampleCache = [:]
        dayTileIndexCache = [:]
        dayTileIndexSourceCount = -1
        previewPolylineCache = [:]
        previewCacheSourceCount = -1
        availableDays = loaded.availableDays
        availableDayKeys = Set(loaded.availableDays.map(dayKey))
        countryISO2 = loaded.countryISO2

        if let last = points.last?.coord {
            lastAccepted = CLLocation(latitude: last.lat, longitude: last.lon)
        } else {
            lastAccepted = nil
        }
    }

    private func scheduleBackgroundDayIndexBuild() {
        pendingDayIndexBuild?.cancel()
        dayIndexBuildGeneration &+= 1
        let generation = dayIndexBuildGeneration
        let snapshot = points
        let work = DispatchWorkItem {
            var grouped: [String: [CoordinateCodable]] = [:]
            grouped.reserveCapacity(32)
            for point in snapshot {
                let key = Self.dayKeyString(for: point.timestamp)
                grouped[key, default: []].append(point.coord)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.dayIndexBuildGeneration else { return }
                self.dayCoordsCache = grouped
            }
        }
        pendingDayIndexBuild = work
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    private func incrementalDayIndexAppend(coord: CoordinateCodable, timestamp: Date) {
        let key = Self.dayKeyString(for: timestamp)
        dayCoordsCache[key, default: []].append(coord)
    }

    private nonisolated static func loadState(from persistURL: URL, deltaURL: URL, moodURL: URL) async -> LoadedState {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let moodFallback = loadMoodState(from: moodURL)
                let legacyFallbackTS = unknownHistoricalTimestamp()
                guard
                    let data = try? Data(contentsOf: persistURL),
                    let payload = try? JSONDecoder().decode(PersistedPayload.self, from: data)
                else {
                    let replayed = replayDelta(base: [], deltaURL: deltaURL, fallbackTimestamp: legacyFallbackTS)
                    let replayedCoords = replayed.map(\.coord)
                    continuation.resume(returning: LoadedState(
                        points: replayed,
                        coordinates: replayedCoords,
                        isEnabled: true,
                        archivedJourneyIDs: [],
                        moodByDay: moodFallback,

                        cachedDistanceMeters: computeTotalDistanceMeters(coords: replayedCoords),
                        availableDays: computeAvailableDays(from: replayed),
                        countryISO2: nil
                    ))
                    return
                }

                let loadedPoints: [LifelogTrackPoint]
                if let payloadPoints = payload.points, !payloadPoints.isEmpty {
                    loadedPoints = payloadPoints
                } else {
                    let fallbackTS = legacyFallbackTS
                    loadedPoints = payload.coordinates.map { LifelogTrackPoint($0, timestamp: fallbackTS) }
                }

                let mergedPoints = replayDelta(base: loadedPoints, deltaURL: deltaURL, fallbackTimestamp: legacyFallbackTS)
                let loadedCoordinates = mergedPoints.map(\.coord)
                // Use cached distance/days if no delta was replayed (counts match).
                let deltaApplied = mergedPoints.count != loadedPoints.count
                let distance = (!deltaApplied && payload.cachedDistanceMeters != nil)
                    ? payload.cachedDistanceMeters!
                    : computeTotalDistanceMeters(coords: loadedCoordinates)
                let days = (!deltaApplied && payload.cachedAvailableDays != nil)
                    ? payload.cachedAvailableDays!
                    : computeAvailableDays(from: mergedPoints)
                continuation.resume(returning: LoadedState(
                    points: mergedPoints,
                    coordinates: loadedCoordinates,
                    isEnabled: payload.isEnabled,
                    archivedJourneyIDs: Set(payload.archivedJourneyIDs ?? []),
                    moodByDay: mergeMoodState(primary: payload.moodByDay, fallback: moodFallback),
                    cachedDistanceMeters: distance,
                    availableDays: days,
                    countryISO2: nil
                ))
            }
        }
    }

    private nonisolated static func replayDelta(
        base: [LifelogTrackPoint],
        deltaURL: URL,
        fallbackTimestamp: Date
    ) -> [LifelogTrackPoint] {
        guard let raw = try? String(contentsOf: deltaURL, encoding: .utf8), !raw.isEmpty else {
            return base
        }

        var out = base
        let decoder = JSONDecoder()
        let lines = raw.split(separator: "\n")
        var lastLineCorrupt = false
        for (i, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            guard let lineData = line.data(using: .utf8) else { continue }

            if let chunk = try? decoder.decode([LifelogTrackPoint].self, from: lineData) {
                appendDeltaChunk(chunk, into: &out)
                continue
            }
            if let coords = try? decoder.decode([CoordinateCodable].self, from: lineData) {
                let fallbackTS = out.last?.timestamp ?? fallbackTimestamp
                let chunk = coords.map { LifelogTrackPoint($0, timestamp: fallbackTS) }
                appendDeltaChunk(chunk, into: &out)
                continue
            }
            // Only the last line can be a crash-truncated partial write; earlier bad lines are truly corrupt.
            if i == lines.count - 1 {
                lastLineCorrupt = true
                print("⚠️ lifelog delta: truncating corrupt last line (\(line.prefix(60))…)")
            }
        }
        // Repair: rewrite the delta file without the corrupt trailing line.
        if lastLineCorrupt {
            repairDeltaFile(deltaURL, validLineCount: lines.count - 1, lines: lines)
        }
        return out
    }

    private nonisolated static func repairDeltaFile(_ url: URL, validLineCount: Int, lines: [Substring]) {
        let valid = lines.prefix(validLineCount).joined(separator: "\n")
        guard var data = valid.data(using: .utf8) else { return }
        if !data.isEmpty { data.append(0x0A) }
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func appendDeltaChunk(_ chunk: [LifelogTrackPoint], into out: inout [LifelogTrackPoint]) {
        for point in chunk {
            if let last = out.last,
               last.lat == point.lat,
               last.lon == point.lon,
               last.timestamp == point.timestamp {
                continue
            }
            out.append(point)
        }
    }

    private nonisolated static func loadMoodState(from moodURL: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: moodURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private nonisolated static func mergeMoodState(
        primary: [String: String]?,
        fallback: [String: String]
    ) -> [String: String] {
        var merged = fallback
        for (key, value) in primary ?? [:] {
            merged[key] = value
        }
        return merged
    }

    private nonisolated static func computeTotalDistanceMeters(coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].lat, longitude: coords[i - 1].lon)
            let b = CLLocation(latitude: coords[i].lat, longitude: coords[i].lon)
            total += b.distance(from: a)
        }
        return total
    }

    private nonisolated static func computeAvailableDays(from points: [LifelogTrackPoint]) -> [Date] {
        let cal = Calendar.current
        let uniq = Set(points.map { cal.startOfDay(for: $0.timestamp) })
        return uniq.sorted(by: >)
    }

    private nonisolated static func unknownHistoricalTimestamp() -> Date {
        // Legacy records without timestamps should never be treated as "today".
        Date(timeIntervalSince1970: 0)
    }

    func bind(to hub: LocationHub) {
        pendingBindHub = hub
        countryISO2 = Self.normalizedISO2(hub.countryISO2)
        guard hasLoaded else {
            bag.removeAll()
            return
        }
        activateBindings(to: hub)
    }

    private func activateBindings(to hub: LocationHub) {
        bag.removeAll()
        pendingBindHub = nil
        countryISO2 = Self.normalizedISO2(hub.countryISO2)

        hub.locationStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.ingest(loc)
            }
            .store(in: &bag)

        hub.$countryISO2
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iso in
                self?.countryISO2 = Self.normalizedISO2(iso)
            }
            .store(in: &bag)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        AppSettings.setPassiveLifelogEnabled(enabled)
        persistAsync()
    }

    var hasTrack: Bool { coordinates.count >= 2 }
    var totalDistanceMeters: Double { cachedDistanceMeters }

    /// Call from debug console: `LifelogStore.shared.diagnosePassiveGaps()`
    /// Prints today's point gap analysis to console.
    func diagnosePassiveGaps() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayPoints = points.filter { $0.timestamp >= todayStart }

        guard todayPoints.count >= 2 else {
            print("📊 [Lifelog Diag] Today has \(todayPoints.count) points — not enough to analyze.")
            return
        }

        var gaps: [(distanceM: Double, timeSec: Double)] = []
        for i in 1..<todayPoints.count {
            let prev = todayPoints[i - 1]
            let curr = todayPoints[i]
            let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
            let b = CLLocation(latitude: curr.lat, longitude: curr.lon)
            let dist = b.distance(from: a)
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            gaps.append((dist, dt))
        }

        let distances = gaps.map(\.distanceM).sorted()
        let times = gaps.map(\.timeSec).sorted()

        let bigGaps = gaps.filter { $0.distanceM > 200 }
        let hugeGaps = gaps.filter { $0.distanceM > 500 }
        let longPauses = gaps.filter { $0.timeSec > 120 }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"

        print("📊 ═══════════════════════════════════════════")
        print("📊 LIFELOG PASSIVE GAP DIAGNOSIS — \(fmt.string(from: todayStart))")
        print("📊 ═══════════════════════════════════════════")
        print("📊 Total points today: \(todayPoints.count)")
        print("📊 Time range: \(fmt.string(from: todayPoints.first!.timestamp)) → \(fmt.string(from: todayPoints.last!.timestamp))")
        print("📊")
        print("📊 Distance between consecutive points:")
        print("📊   Min:    \(String(format: "%.0f", distances.first!))m")
        print("📊   Median: \(String(format: "%.0f", distances[distances.count / 2]))m")
        print("📊   P90:    \(String(format: "%.0f", distances[Int(Double(distances.count) * 0.9)]))m")
        print("📊   P99:    \(String(format: "%.0f", distances[Int(Double(distances.count) * 0.99)]))m")
        print("📊   Max:    \(String(format: "%.0f", distances.last!))m")
        print("📊")
        print("📊 Time between consecutive points:")
        print("📊   Min:    \(String(format: "%.0f", times.first!))s")
        print("📊   Median: \(String(format: "%.0f", times[times.count / 2]))s")
        print("📊   P90:    \(String(format: "%.0f", times[Int(Double(times.count) * 0.9)]))s")
        print("📊   Max:    \(String(format: "%.0f", times.last!))s")
        print("📊")
        print("📊 Gaps > 200m: \(bigGaps.count) / \(gaps.count)")
        print("📊 Gaps > 500m: \(hugeGaps.count) / \(gaps.count)")
        print("📊 Pauses > 2min: \(longPauses.count) / \(gaps.count)")
        print("📊")

        if !bigGaps.isEmpty {
            print("📊 ── Top 10 biggest distance gaps ──")
            let topByDist = gaps.enumerated()
                .sorted { $0.element.distanceM > $1.element.distanceM }
                .prefix(10)
            for item in topByDist {
                let idx = item.offset
                let g = item.element
                let t0 = fmt.string(from: todayPoints[idx].timestamp)
                let t1 = fmt.string(from: todayPoints[idx + 1].timestamp)
                print("📊   \(t0) → \(t1)  dist=\(String(format: "%.0f", g.distanceM))m  dt=\(String(format: "%.0f", g.timeSec))s")
            }
        }

        if !longPauses.isEmpty {
            print("📊 ── Top 10 longest time gaps ──")
            let topByTime = gaps.enumerated()
                .sorted { $0.element.timeSec > $1.element.timeSec }
                .prefix(10)
            for item in topByTime {
                let idx = item.offset
                let g = item.element
                let t0 = fmt.string(from: todayPoints[idx].timestamp)
                let t1 = fmt.string(from: todayPoints[idx + 1].timestamp)
                print("📊   \(t0) → \(t1)  dist=\(String(format: "%.0f", g.distanceM))m  dt=\(String(format: "%.0f", g.timeSec))s")
            }
        }

        print("📊 ═══════════════════════════════════════════")
        if hugeGaps.count > 0 {
            print("📊 VERDICT: \(hugeGaps.count) gaps > 500m → iOS is pausing location updates.")
            print("📊 FIX: Set pausesLocationUpdatesAutomatically = false")
        } else if bigGaps.count > 3 {
            print("📊 VERDICT: Multiple 200m+ gaps → distance filter too aggressive.")
            print("📊 FIX: Lower distanceFilter and adaptive min distance")
        } else {
            print("📊 VERDICT: Collection looks OK — issue is likely in rendering pipeline.")
        }
        print("📊 ═══════════════════════════════════════════")
    }

    private func ingest(_ loc: CLLocation) {
        currentLocation = loc
        guard isEnabled else { return }
        // Journey in-progress owns point storage; Lifelog only stores passive points.
        if TrackingService.shared.isTracking { return }
        guard loc.horizontalAccuracy >= 0 else { return }
        guard shouldAcceptPassiveLocation(loc) else { return }
        guard passesPassiveAccuracyGate(loc) || shouldAcceptLongGapFallback(loc) else { return }

        if let last = lastAccepted {
            let moved = loc.distance(from: last)
            let adaptiveMinDistance = max(
                minDistanceMeters,
                min(max(loc.horizontalAccuracy * 0.5, 12), 40)
            )
            if moved < adaptiveMinDistance {
                return
            }
        }

        let c = CoordinateCodable(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        if let prev = points.last?.coord,
           abs(prev.lat - c.lat) < 0.0000005,
           abs(prev.lon - c.lon) < 0.0000005 {
            return
        }

        if let prev = points.last?.coord {
            let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
            let b = CLLocation(latitude: c.lat, longitude: c.lon)
            cachedDistanceMeters += b.distance(from: a)
        }

        let appendedPoint = LifelogTrackPoint(
            c,
            timestamp: loc.timestamp,
            accuracy: loc.horizontalAccuracy
        )
        points.append(appendedPoint)
        coordinates.append(c)
        dirtyPointDayKeys.insert(dayKey(loc.timestamp))
        enqueueCountryAttribution(for: [appendedPoint])
        invalidatePolylineCaches()
        lastAccepted = loc
        let hadTrackedDays = !availableDayKeys.isEmpty
        let didInsertDay = insertAvailableDayIfNeeded(loc.timestamp)
        requestGlobeRefreshForPassiveDayRolloverIfNeeded(
            hadTrackedDays: hadTrackedDays,
            didInsertDay: didInsertDay
        )
        incrementalDayIndexAppend(coord: c, timestamp: loc.timestamp)
        appendDelta(points: [appendedPoint])
        persistAsync()
        scheduleTrackTileRevisionBump()
    }

    private func shouldAcceptPassiveLocation(_ loc: CLLocation) -> Bool {
        let speed = max(loc.speed, 0)
        let motion = motionHub.snapshot

        guard let anchor = passiveMotionAnchor else {
            passiveMotionAnchor = loc
            passiveMotionAnchorTimestamp = loc.timestamp
            passiveMotionState = .moving
            return true
        }

        let moved = loc.distance(from: anchor)
        let dt = loc.timestamp.timeIntervalSince(passiveMotionAnchorTimestamp)

        switch passiveMotionState {
        case .moving:
            let gpsExitCandidate = speed >= stationaryExitSpeedMetersPerSecond || moved >= stationaryExitDistanceMeters
            if gpsExitCandidate {
                passiveMotionAnchor = loc
                passiveMotionAnchorTimestamp = loc.timestamp
                return true
            }
            let gpsStationaryCandidate = dt >= stationaryEnterWindow && moved <= stationaryClusterRadiusMeters
            if PassiveMotionFusion.shouldEnterStationary(
                gpsStationaryCandidate: gpsStationaryCandidate,
                motion: motion
            ) {
                passiveMotionState = .stationary
                passiveMotionAnchor = loc
                passiveMotionAnchorTimestamp = loc.timestamp
                return false
            }
            if dt >= 90 {
                passiveMotionAnchor = loc
                passiveMotionAnchorTimestamp = loc.timestamp
            }
            return true

        case .stationary:
            let gpsExitCandidate = speed >= stationaryExitSpeedMetersPerSecond || moved >= stationaryExitDistanceMeters
            if PassiveMotionFusion.shouldExitStationary(
                gpsExitCandidate: gpsExitCandidate,
                motion: motion
            ) {
                passiveMotionState = .moving
                passiveMotionAnchor = loc
                passiveMotionAnchorTimestamp = loc.timestamp
                return true
            }
            if dt >= 5 * 60 {
                passiveMotionAnchor = loc
                passiveMotionAnchorTimestamp = loc.timestamp
            }
            return false
        }
    }

    private func passesPassiveAccuracyGate(_ loc: CLLocation) -> Bool {
        let limit: CLLocationAccuracy = (passiveMotionState == .moving)
            ? maxAcceptedHorizontalAccuracyMoving
            : maxAcceptedHorizontalAccuracyStationary
        return loc.horizontalAccuracy <= limit
    }

    private func shouldAcceptLongGapFallback(_ loc: CLLocation) -> Bool {
        guard passiveMotionState == .moving else { return false }
        guard loc.horizontalAccuracy <= longGapFallbackMaxAccuracy else { return false }
        guard let lastAccepted else { return false }

        let dt = loc.timestamp.timeIntervalSince(lastAccepted.timestamp)
        guard dt >= longGapFallbackInterval else { return false }

        let moved = loc.distance(from: lastAccepted)
        return moved >= longGapFallbackDistanceMeters
    }

    private func resetPassiveMotionState() {
        passiveMotionState = .moving
        passiveMotionAnchor = nil
        passiveMotionAnchorTimestamp = .distantPast
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

        if !coords.isEmpty {
            let timeline = timestampsForJourney(journey, count: coords.count)
            let imported = zip(coords, timeline).map { (coord: $0.0, timestamp: $0.1) }
            importExternalTrack(points: imported, source: .archive)
        }

        archivedJourneyIDs.insert(journeyID)
        if persistAfter { persistAsync() }
        return true
    }

    func importExternalTrack(
        points imported: [(coord: CoordinateCodable, timestamp: Date)],
        source: ExternalTrackImportSource = .archive
    ) {
        guard !imported.isEmpty else { return }
        var appended: [LifelogTrackPoint] = []
        for item in imported {
            let coord = item.coord
            let timestamp = item.timestamp

            if let prev = points.last?.coord,
               abs(prev.lat - coord.lat) < 0.0000005,
               abs(prev.lon - coord.lon) < 0.0000005 {
                continue
            }

            if let prev = points.last?.coord {
                let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
                let b = CLLocation(latitude: coord.lat, longitude: coord.lon)
                cachedDistanceMeters += b.distance(from: a)
            }

            let appendedPoint = LifelogTrackPoint(coord, timestamp: timestamp)
            points.append(appendedPoint)
            appended.append(appendedPoint)
            coordinates.append(coord)
            dirtyPointDayKeys.insert(dayKey(timestamp))
        }

        guard !appended.isEmpty else { return }
        enqueueCountryAttribution(for: appended)
        invalidatePolylineCaches()
        let hadTrackedDays = !availableDayKeys.isEmpty
        let didInsertDay = mergeAvailableDays(from: appended.map(\.timestamp))
        if source == .passiveRecovery {
            requestGlobeRefreshForPassiveDayRolloverIfNeeded(
                hadTrackedDays: hadTrackedDays,
                didInsertDay: didInsertDay
            )
        }
        appendDelta(points: appended)
        persistAsync()
        scheduleBackgroundDayIndexBuild()
        scheduleTrackTileRevisionBump()
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

    func snapshotPointsByDay() -> [String: [LifelogTrackPoint]] {
        Dictionary(grouping: points, by: { dayKey($0.timestamp) })
    }

    func snapshotDirtyPointsByDay() -> [String: [LifelogTrackPoint]] {
        guard !dirtyPointDayKeys.isEmpty else { return [:] }
        let all = snapshotPointsByDay()
        return dirtyPointDayKeys.reduce(into: [String: [LifelogTrackPoint]]()) { partial, key in
            if let points = all[key] {
                partial[key] = points
            }
        }
    }

    func snapshotMoodByDay() -> [String: String] {
        moodByDay
    }

    func snapshotDirtyMoodByDay() -> [String: String] {
        guard !dirtyMoodDayKeys.isEmpty else { return [:] }
        return dirtyMoodDayKeys.reduce(into: [String: String]()) { partial, key in
            if let mood = moodByDay[key] {
                partial[key] = mood
            }
        }
    }

    func snapshotDeletedMoodDayKeys() -> [String] {
        Array(deletedMoodDayKeys)
    }

    func setMood(_ mood: String?, for day: Date) {
        let key = dayKey(day)
        if let mood, !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            moodByDay[key] = mood
            dirtyMoodDayKeys.insert(key)
            deletedMoodDayKeys.remove(key)
        } else {
            moodByDay.removeValue(forKey: key)
            dirtyMoodDayKeys.remove(key)
            deletedMoodDayKeys.insert(key)
        }
        persistMoodSnapshotNow()
        pendingSnapshotPersist?.cancel()
        pendingSnapshotPersist = nil
        persistSnapshotNow()
    }

    func mergeCloudRestore(
        dayBatches: [String: [LifelogTrackPoint]],
        deletedDayKeys: [String],
        moodByDay restoredMoodByDay: [String: String],
        deletedMoodDayKeys: [String]
    ) {
        let touchedDayKeys = Set(dayBatches.keys).union(deletedDayKeys)
        var mergedPoints = points.filter { point in
            !touchedDayKeys.contains(dayKey(point.timestamp))
        }
        mergedPoints.append(contentsOf: dayBatches.values.flatMap { $0 })
        mergedPoints.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        var mergedMoodByDay = moodByDay
        deletedMoodDayKeys.forEach { mergedMoodByDay.removeValue(forKey: $0) }
        restoredMoodByDay.forEach { mergedMoodByDay[$0.key] = $0.value }

        let nextState = LoadedState(
            points: mergedPoints,
            coordinates: mergedPoints.map(\.coord),
            isEnabled: isEnabled,
            archivedJourneyIDs: archivedJourneyIDs,
            moodByDay: mergedMoodByDay,
            cachedDistanceMeters: totalDistanceMeters(coords: mergedPoints.map(\.coord)),
            availableDays: Self.computeAvailableDays(from: mergedPoints),
            countryISO2: countryISO2
        )
        applyLoadedState(nextState)
        dirtyPointDayKeys.subtract(touchedDayKeys)
        dirtyMoodDayKeys.subtract(Set(restoredMoodByDay.keys))
        dirtyMoodDayKeys.subtract(Set(deletedMoodDayKeys))
        self.deletedMoodDayKeys.subtract(Set(restoredMoodByDay.keys))
        self.deletedMoodDayKeys.subtract(Set(deletedMoodDayKeys))
        scheduleBackgroundDayIndexBuild()
        persistSnapshotNow()
        bumpTrackTileRevision()
    }

    func clearDirtyCloudSyncState(
        uploadedPointDayKeys: [String],
        uploadedMoodDayKeys: [String],
        deletedMoodDayKeys: [String]
    ) {
        dirtyPointDayKeys.subtract(uploadedPointDayKeys)
        dirtyMoodDayKeys.subtract(uploadedMoodDayKeys)
        self.deletedMoodDayKeys.subtract(deletedMoodDayKeys)
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
        guard hasLoaded else { return }
        pendingSnapshotPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistSnapshotNow()
        }
        pendingSnapshotPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotPersistDebounce, execute: work)
    }

    private func appendDelta(points appended: [LifelogTrackPoint]) {
        guard !appended.isEmpty else { return }
        let target = deltaURL
        let baseDir = target.deletingLastPathComponent()
        let chunk = appended
        fileIOQueue.async {
            do {
                try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
                var data = try JSONEncoder().encode(chunk)
                data.append(0x0A)
                if FileManager.default.fileExists(atPath: target.path) {
                    let handle = try FileHandle(forWritingTo: target)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try data.write(to: target, options: .atomic)
                }
            } catch {
                print("❌ lifelog delta append failed:", error)
            }
        }
    }

    private func persistSnapshotNow() {
        guard hasLoaded else { return }
        let payload = PersistedPayload(
            points: points,
            coordinates: coordinates,
            isEnabled: isEnabled,
            archivedJourneyIDs: Array(archivedJourneyIDs),
            moodByDay: moodByDay,
            cachedDistanceMeters: cachedDistanceMeters,
            cachedAvailableDays: availableDays
        )
        let url = persistURL
        let delta = deltaURL
        let moodURL = moodPersistURL
        let moodSnapshot = moodByDay
        fileIOQueue.async {
            do {
                let data = try JSONEncoder().encode(payload)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                if FileManager.default.fileExists(atPath: delta.path) {
                    try? FileManager.default.removeItem(at: delta)
                }
            } catch {
                print("❌ lifelog save failed:", error)
            }
            Self.persistMoodSnapshot(moodSnapshot, to: moodURL)
        }
    }

    private func persistMoodSnapshotNow() {
        let snapshot = moodByDay
        Self.persistMoodSnapshot(snapshot, to: moodPersistURL)
    }

    private nonisolated static func persistMoodSnapshot(_ moodSnapshot: [String: String], to moodURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: moodURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let moodData = try JSONEncoder().encode(moodSnapshot)
            try moodData.write(to: moodURL, options: .atomic)
        } catch {
            print("❌ lifelog mood save failed:", error)
        }
    }

    func flushPersistNow() {
        guard hasLoaded else { return }
        pendingSnapshotPersist?.cancel()
        pendingSnapshotPersist = nil
        persistSnapshotNow()
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

    @discardableResult
    private func mergeAvailableDays(from timestamps: [Date]) -> Bool {
        guard !timestamps.isEmpty else { return false }
        var didInsert = false
        for timestamp in timestamps {
            didInsert = insertAvailableDayIfNeeded(timestamp) || didInsert
        }
        if didInsert {
            availableDays.sort(by: >)
        }
        return didInsert
    }

    @discardableResult
    private func insertAvailableDayIfNeeded(_ timestamp: Date) -> Bool {
        let key = dayKey(timestamp)
        guard availableDayKeys.insert(key).inserted else { return false }
        availableDays.append(Calendar.current.startOfDay(for: timestamp))
        return true
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
        Self.dayKeyString(for: day)
    }

    private func requestGlobeRefreshForPassiveDayRolloverIfNeeded(
        hadTrackedDays: Bool,
        didInsertDay: Bool
    ) {
        guard hadTrackedDays, didInsertDay else { return }
        GlobeRefreshCoordinator.shared.requestRefresh(reason: .passiveDayRolledOver)
    }

    private func enqueueCountryAttribution(for appended: [LifelogTrackPoint]) {
        guard !appended.isEmpty else { return }
        let inputs = appended.map {
            LifelogCountryAttributionPointInput(
                pointID: $0.id,
                cellID: $0.cellID,
                coordinate: $0.coord
            )
        }
        let coordinator = attributionCoordinator
        Task(priority: .utility) {
            await coordinator.enqueue(points: inputs)
        }
    }

    private nonisolated static func dayKeyString(for day: Date) -> String {
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month, .day], from: cal.startOfDay(for: day))
        let y = parts.year ?? 1970
        let m = parts.month ?? 1
        let d = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints, maxPoints >= 2 else { return coords }

        // --- Ramer-Douglas-Peucker (shape-preserving simplification) ---

        // Perpendicular distance from point C to line segment A-B, in approximate meters.
        func perpendicularDistance(_ c: CoordinateCodable, _ a: CoordinateCodable, _ b: CoordinateCodable) -> Double {
            let dLat = b.lat - a.lat
            let dLon = b.lon - a.lon
            let lenSq = dLat * dLat + dLon * dLon
            guard lenSq > 1e-20 else {
                let dx = (c.lat - a.lat) * 111_320
                let dy = (c.lon - a.lon) * 111_320 * cos(a.lat * .pi / 180)
                return sqrt(dx * dx + dy * dy)
            }
            let t = max(0, min(1, ((c.lat - a.lat) * dLat + (c.lon - a.lon) * dLon) / lenSq))
            let projLat = a.lat + t * dLat
            let projLon = a.lon + t * dLon
            let dx = (c.lat - projLat) * 111_320
            let dy = (c.lon - projLon) * 111_320 * cos(c.lat * .pi / 180)
            return sqrt(dx * dx + dy * dy)
        }

        // Iterative RDP using explicit stack (avoids stack overflow on large inputs).
        func rdp(_ points: [CoordinateCodable], epsilon: Double) -> [CoordinateCodable] {
            guard points.count > 2 else { return points }
            var keep = [Bool](repeating: false, count: points.count)
            keep[0] = true
            keep[points.count - 1] = true

            var stack: [(Int, Int)] = [(0, points.count - 1)]
            while let (startIdx, endIdx) = stack.popLast() {
                guard endIdx - startIdx > 1 else { continue }
                var maxDist: Double = 0
                var farthest = startIdx
                for i in (startIdx + 1)..<endIdx {
                    let d = perpendicularDistance(points[i], points[startIdx], points[endIdx])
                    if d > maxDist {
                        maxDist = d
                        farthest = i
                    }
                }
                if maxDist > epsilon {
                    keep[farthest] = true
                    stack.append((startIdx, farthest))
                    stack.append((farthest, endIdx))
                }
            }
            return (0..<points.count).compactMap { keep[$0] ? points[$0] : nil }
        }

        // Binary search for an epsilon that yields ≤ maxPoints.
        var lo: Double = 0.1    // ~0.1 meter
        var hi: Double = 5000.0 // ~5 km
        var bestResult = coords
        for _ in 0..<16 {
            let mid = (lo + hi) / 2.0
            let result = rdp(coords, epsilon: mid)
            if result.count <= maxPoints {
                bestResult = result
                hi = mid
            } else {
                lo = mid
            }
        }

        // If RDP still exceeds budget (shouldn't normally happen), uniform fallback.
        if bestResult.count > maxPoints {
            let n = bestResult.count
            var uniform: [CoordinateCodable] = []
            uniform.reserveCapacity(maxPoints)
            for i in 0..<maxPoints {
                let t = Double(i) / Double(maxPoints - 1)
                let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
                uniform.append(bestResult[min(max(idx, 0), n - 1)])
            }
            bestResult = uniform
        }

        // Deduplicate consecutive identical points.
        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(bestResult.count)
        for c in bestResult {
            if let last = compact.last, last.lat == c.lat, last.lon == c.lon {
                continue
            }
            compact.append(c)
        }
        return compact
    }

    private func invalidatePolylineCaches() {
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

    private static func normalizedISO2(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let iso = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
    }

    func trackRenderEvents() -> [TrackRenderEvent] {
        Self.makeTrackRenderEvents(from: points)
    }

    func trackRenderEventsAsync() async -> [TrackRenderEvent] {
        let snapshot = points
        return await Task.detached(priority: .utility) {
            Self.makeTrackRenderEvents(from: snapshot)
        }.value
    }

    func passiveCountryRuns(day: Date? = nil) async -> [LifelogAttributedCoordinateRun] {
        let pointsSnapshot = points
        let attributionSnapshot = await attributionCoordinator.loadSnapshot()
        return await Task.detached(priority: .utility) {
            Self.makePassiveCountryRuns(
                from: pointsSnapshot,
                attribution: attributionSnapshot,
                day: day
            )
        }.value
    }

    private nonisolated static func makeTrackRenderEvents(from points: [LifelogTrackPoint]) -> [TrackRenderEvent] {
        points.map {
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: $0.timestamp,
                coordinate: $0.coord
            )
        }
    }

    private nonisolated static func makePassiveCountryRuns(
        from points: [LifelogTrackPoint],
        attribution: LifelogCountryAttributionSnapshot,
        day: Date?
    ) -> [LifelogAttributedCoordinateRun] {
        guard !points.isEmpty else { return [] }

        let calendar = Calendar.current
        let targetDay = day.map { calendar.startOfDay(for: $0) }
        let indexByPointID = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.id, $0.offset) })

        return attribution.runs.compactMap { run in
            guard let startIndex = indexByPointID[run.startPointID],
                  let endIndex = indexByPointID[run.endPointID] else {
                return nil
            }

            let lower = min(startIndex, endIndex)
            let upper = max(startIndex, endIndex)
            var slice = Array(points[lower...upper])
            if let targetDay {
                slice = slice.filter { calendar.startOfDay(for: $0.timestamp) == targetDay }
            }
            guard slice.count >= 2 else { return nil }

            return LifelogAttributedCoordinateRun(
                sourceType: .passive,
                coordsWGS84: slice.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                },
                countryISO2: run.iso2,
                startTimestamp: slice.first?.timestamp ?? .distantPast,
                endTimestamp: slice.last?.timestamp ?? .distantPast
            )
        }
    }

    private func bumpTrackTileRevision() {
        trackTileRevision &+= 1
        NotificationCenter.default.post(
            name: .lifelogStoreTrackTilesDidChange,
            object: self,
            userInfo: ["revision": trackTileRevision]
        )
    }

    private func scheduleTrackTileRevisionBump() {
        if trackTileRevisionDebounce <= 0 {
            bumpTrackTileRevision()
            return
        }
        pendingTrackTileRevisionBump?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.bumpTrackTileRevision()
        }
        pendingTrackTileRevisionBump = work
        DispatchQueue.main.asyncAfter(deadline: .now() + trackTileRevisionDebounce, execute: work)
    }
}
