import Foundation
import Combine

extension Notification.Name {
    static let journeyStoreDidDiscardJourneys = Notification.Name("journeyStoreDidDiscardJourneys")
    static let journeyStoreTrackTilesDidChange = Notification.Name("journeyStoreTrackTilesDidChange")
}

/// Stores the ordered list of journey IDs.
/// Keeping this tiny lets us load list screens quickly and avoid decoding big routes.
final class JourneysIndexStore {
    private let fm = FileManager.default
    private let filename = "index.json"
    private let baseURL: URL

    /// `baseURL` is the user-scoped journeys directory (e.g. .../<userID>/Journeys).
    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    private var url: URL { baseURL.appendingPathComponent(filename) }

    private func ensureBaseDir() throws {
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func loadJourneyIDs() throws -> [String] {
        guard fm.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    func loadJourneyIDsAsync() async -> [String] {
        let fileURL = url
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continuation.resume(returning: [])
                    return
                }
                do {
                    let data = try Data(contentsOf: fileURL)
                    let ids = try JSONDecoder().decode([String].self, from: data)
                    continuation.resume(returning: ids)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func replaceIDs(_ ids: [String]) throws {
        try ensureBaseDir()
        let data = try JSONEncoder().encode(ids)
        try data.write(to: url, options: .atomic)
    }

    /// Upsert `id` to the front (most recent first).
    func upsertIDFirst(_ id: String) throws {
        var ids = (try? loadJourneyIDs()) ?? []
        ids.removeAll(where: { $0 == id })
        ids.insert(id, at: 0)
        try replaceIDs(ids)
    }

    /// Remove one id from index if present.
    func removeID(_ id: String) throws {
        var ids = (try? loadJourneyIDs()) ?? []
        ids.removeAll(where: { $0 == id })
        try replaceIDs(ids)
    }
}

@MainActor
final class JourneyStore: ObservableObject {
    struct SyncHooks {
        var upsertCompletedJourney: ((JourneyRoute) -> Void)?
        var deleteJourney: ((String) -> Void)?

        static let disabled = SyncHooks(
            upsertCompletedJourney: nil,
            deleteJourney: nil
        )
    }

    @Published private(set) var journeys: [JourneyRoute] = []
    @Published var latestOngoing: JourneyRoute? = nil
    @Published private(set) var hasLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var trackTileRevision: Int = 0
    /// Bumped on metadata/memory changes that don't affect coordinates or journey count.
    /// Memory pages observe this instead of trackTileRevision to avoid coordinate-update noise.
    @Published private(set) var metadataRevision: Int = 0
    var syncHooks: SyncHooks = .disabled

    private var fileStore: JourneysFileStore
    private var indexStore: JourneysIndexStore
    private var userID: String

    private let ioQueue = DispatchQueue(label: "ss.journeys.store", qos: .utility)

    // =======================================================
    // MARK: - Persistence (mode-driven delta + lightweight meta)
    // =======================================================

    /// Track which journey the persistence counters belong to.
    private var currentPersistJourneyId: String? = nil

    /// Track the last seen coordinate count (to detect "meta-only" changes).
    private var lastSeenCoordCount: Int = 0

    /// Delta persistence: append-only coordinate chunks while tracking.
    private var lastDeltaPersistCoordCount: Int = 0
    private var lastDeltaPersistAt: Date = .distantPast

    /// Debounced persistence for small metadata-only snapshots (memories/cityKey/etc),
    /// used when coordCount did NOT change (e.g. user edited a memory).
    private var pendingMetaPersist: DispatchWorkItem?
    private let metaPersistDebounce: TimeInterval = 0.6

    init(paths: StoragePath) {
        self.userID = paths.userID
        self.fileStore = JourneysFileStore(baseURL: paths.journeysDir)
        self.indexStore = JourneysIndexStore(baseURL: paths.journeysDir)
    }

    func rebind(paths: StoragePath) {
        pendingMetaPersist?.cancel()
        pendingMetaPersist = nil
        currentPersistJourneyId = nil
        lastSeenCoordCount = 0
        lastDeltaPersistCoordCount = 0
        lastDeltaPersistAt = .distantPast
        latestOngoing = nil
        journeys = []
        hasLoaded = false
        trackTileRevision = 0

        userID = paths.userID
        fileStore = JourneysFileStore(baseURL: paths.journeysDir)
        indexStore = JourneysIndexStore(baseURL: paths.journeysDir)
        bumpTrackTileRevision()
    }

    /// Populate in-memory journeys directly without disk I/O.
    /// Used by FriendMirrorContext to avoid async loading flash.
    func loadFromMemory(_ routes: [JourneyRoute]) {
        self.journeys = routes
        self.latestOngoing = nil
        self.hasLoaded = true
        self.bumpTrackTileRevision()
    }

    /// Load journeys from file-backed store.
    func load() {
        Task {
            await self.loadAsync()
        }
    }

    func loadAsync() async {
        guard !isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }

        // All disk I/O (index read, orphan scan, journey file reads) runs on a
        // background queue. Only the final property assignments hop to MainActor.
        let fStore = fileStore
        let iStore = indexStore
        let loaded = await withCheckedContinuation { (cont: CheckedContinuation<[JourneyRoute], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var ids = (try? iStore.loadJourneyIDs()) ?? []

                // Recover orphaned journey files not listed in index.
                let orphanIDs = fStore.scanOrphanedIDs(knownIDs: Set(ids))
                if !orphanIDs.isEmpty {
                    ids = orphanIDs + ids
                    try? iStore.replaceIDs(ids)
                    print("⚠️ recovered \(orphanIDs.count) orphaned journey(s)")
                }

                guard !ids.isEmpty else {
                    cont.resume(returning: [])
                    return
                }

                var result: [JourneyRoute] = []
                result.reserveCapacity(ids.count)
                for id in ids {
                    if let j = try? fStore.loadJourney(id: id) { result.append(j) }
                }
                cont.resume(returning: result)
            }
        }

        self.journeys = loaded

        guard !loaded.isEmpty else {
            self.latestOngoing = nil
            self.hasLoaded = true
            self.bumpTrackTileRevision()
            return
        }

        // Best-effort: restore "ongoing" journey pointer after a cold start.
        self.latestOngoing = loaded.first(where: { $0.endTime == nil })

        // Pre-seed delta persistence offset so that coordinates already recovered
        // from the delta file are not re-written on the first flush after cold start.
        if let ongoing = self.latestOngoing {
            self.currentPersistJourneyId = ongoing.id
            self.lastDeltaPersistCoordCount = ongoing.coordinates.count
            self.lastSeenCoordCount = ongoing.coordinates.count
        }

        self.hasLoaded = true
        self.bumpTrackTileRevision()
    }

    /// Update in-memory list and schedule persistence.
    /// Call this from TrackingService (NOT from MapView per-point).
    func upsertSnapshotThrottled(_ journey: JourneyRoute, coordCount: Int) {
        // Ensure thumbnails are available everywhere (city cards / globe / share) without falling back to full coords.
        var j = journey
        j.ensureThumbnail(maxPoints: 280)

        // 1) update in-memory list on main
        if j.endTime == nil {
            self.latestOngoing = j
        } else if self.latestOngoing?.id == j.id {
            self.latestOngoing = nil
        }
        if let i = self.journeys.firstIndex(where: { $0.id == j.id }) {
            self.journeys[i] = j
        } else {
            self.journeys.insert(j, at: 0)
        }
        bumpTrackTileRevision()

        // 2) reset counters if we switched to a different journey id
        if currentPersistJourneyId != j.id {
            currentPersistJourneyId = j.id
            lastSeenCoordCount = 0
            lastDeltaPersistCoordCount = 0
            lastDeltaPersistAt = .distantPast
            pendingMetaPersist?.cancel()
            pendingMetaPersist = nil
        }

        let now = Date()
        let coordChanged = (coordCount != lastSeenCoordCount)
        lastSeenCoordCount = coordCount
        let persistInterval = effectiveDeltaPersistInterval(for: j)

        // Completed journey: always finalize immediately (overwrite full file and clean up any delta/meta).
        if j.endTime != nil {
            flushPersist(journey: j, force: true)
            return
        }

        // First snapshot: create disk footprints early (meta + initial delta).
        if lastDeltaPersistAt == .distantPast {
            flushPersist(journey: j, force: true)
            return
        }

        // Meta-only updates (e.g. memory add/edit): persist quickly without touching big coordinates.
        if !coordChanged {
            metadataRevision &+= 1
            scheduleMetaPersist(journey: j)
        }

        // Coordinate delta: write using the active tracking mode cadence.
        if now.timeIntervalSince(lastDeltaPersistAt) >= persistInterval {
            flushPersist(journey: j, force: false)
        }
    }

    /// Flush last snapshot immediately (e.g., onDisappear/background/finish).
    func flushPersist() {
        if let ongoing = latestOngoing {
            flushPersist(journey: ongoing, force: true)
            return
        }
        guard let j = journeys.first else { return }
        flushPersist(journey: j, force: true)
    }

    /// Flush a specific journey immediately.
    ///
    /// Useful for explicit "Save" actions where you want the edit to hit disk right away,
    /// without relying on debounced meta persistence.
    func flushPersist(journey: JourneyRoute) {
        flushPersist(journey: journey, force: true)
        syncCompletedJourneyIfNeeded(journey)
    }

    private func scheduleMetaPersist(journey: JourneyRoute) {
        pendingMetaPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistMetaOnly(journey: journey)
        }
        pendingMetaPersist = work
        ioQueue.asyncAfter(deadline: .now() + metaPersistDebounce, execute: work)
    }

    private func persistMetaOnly(journey: JourneyRoute) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                var meta = journey
                meta.ensureThumbnail(maxPoints: 280)
                try self.fileStore.saveMetaSnapshot(meta)
                try self.indexStore.upsertIDFirst(meta.id)
            } catch {
                print("❌ meta save failed:", error)
            }
        }
    }

    private func flushPersist(journey: JourneyRoute, force: Bool) {
        pendingMetaPersist?.cancel()
        pendingMetaPersist = nil

        var snapshot = journey
        snapshot.ensureThumbnail(maxPoints: 280)
        let config = effectiveConfig(for: snapshot)
        let persistInterval = effectiveDeltaPersistInterval(for: snapshot)

        let now = Date()
        let startIdx = min(lastDeltaPersistCoordCount, snapshot.coordinates.count)
        let endIdx = snapshot.coordinates.count
        let rawNewCoords = (startIdx < endIdx) ? Array(snapshot.coordinates[startIdx..<endIdx]) : []
        let newCoords = downsampleDeltaCoordsIfNeeded(rawNewCoords, config: config)

        let shouldWriteDelta =
            snapshot.endTime == nil &&
            !newCoords.isEmpty &&
            (force || now.timeIntervalSince(lastDeltaPersistAt) >= persistInterval)

        if shouldWriteDelta {
            lastDeltaPersistCoordCount = endIdx
            lastDeltaPersistAt = now
        }

        // Finalized journeys: write synchronously so the caller can be sure the
        // data is durable before the process exits. This prevents the scenario
        // where the UI reports success but the app is killed before the async
        // write reaches disk, causing the journey to revert to "ongoing" on
        // next cold start.
        // ioQueue is a serial utility queue; the caller is on @MainActor, so
        // ioQueue.sync will not deadlock.
        if snapshot.endTime != nil {
            ioQueue.sync { [self] in
                do {
                    try self.indexStore.upsertIDFirst(snapshot.id)
                    try self.fileStore.finalizeJourney(snapshot)
                } catch {
                    print("❌ finalize save failed:", error)
                }
            }
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.indexStore.upsertIDFirst(snapshot.id)
                try self.fileStore.saveMetaSnapshot(snapshot)

                if shouldWriteDelta {
                    try self.fileStore.appendDelta(journeyId: snapshot.id, newCoords: newCoords)
                }
            } catch {
                print("❌ journey save failed:", error)
            }
        }
    }

    private func effectiveConfig(for journey: JourneyRoute) -> TrackingModeConfig {
        TrackingModeConfig.config(for: journey.trackingMode)
    }

    private func effectiveDeltaPersistInterval(for journey: JourneyRoute) -> TimeInterval {
        let config = effectiveConfig(for: journey)
        return max(15, config.deltaPersistInterval)
    }

    private func downsampleDeltaCoordsIfNeeded(_ coords: [CoordinateCodable], config: TrackingModeConfig) -> [CoordinateCodable] {
        guard config.enableStorageDownsample else { return coords }
        guard coords.count > 2 else { return coords }

        let perHour = max(30, config.storageMaxPointsPerHour)
        let interval = max(15, config.deltaPersistInterval)
        let budgetPerFlush = max(2, Int((Double(perHour) * interval / 3600.0).rounded(.up)))
        guard coords.count > budgetPerFlush else { return coords }

        return douglasPeuckerReduce(coords, maxPoints: budgetPerFlush)
    }

    /// Douglas-Peucker simplification: keeps turns, removes points on straight segments.
    /// Always retains first and last points; selects the `maxPoints` most significant points
    /// by perpendicular distance from the simplifying line.
    private func douglasPeuckerReduce(_ coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard maxPoints >= 2 else { return Array(coords.prefix(1)) }
        guard coords.count > maxPoints else { return coords }

        let n = coords.count
        // Assign importance to each point. First/last get max importance so they are always kept.
        var importance = [Double](repeating: 0, count: n)
        importance[0] = .greatestFiniteMagnitude
        importance[n - 1] = .greatestFiniteMagnitude

        func assignImportance(_ start: Int, _ end: Int) {
            guard end - start > 1 else { return }

            let ax = coords[start].lon, ay = coords[start].lat
            let bx = coords[end].lon, by = coords[end].lat
            let midLat = (ay + by) / 2.0
            let lonScale = cos(midLat * .pi / 180.0)
            let dx = (bx - ax) * lonScale
            let dy = by - ay
            let lenSq = dx * dx + dy * dy

            var maxDist = 0.0
            var maxIdx = start + 1
            for i in (start + 1)..<end {
                let px = (coords[i].lon - ax) * lonScale
                let py = coords[i].lat - ay
                let dist: Double
                if lenSq < 1e-20 {
                    dist = sqrt(px * px + py * py)
                } else {
                    dist = abs(px * dy - py * dx) / sqrt(lenSq)
                }
                if dist > maxDist {
                    maxDist = dist
                    maxIdx = i
                }
            }

            importance[maxIdx] = maxDist
            assignImportance(start, maxIdx)
            assignImportance(maxIdx, end)
        }

        assignImportance(0, n - 1)

        // Keep the `maxPoints` most important points, preserving original order.
        var indexed = (0..<n).map { ($0, importance[$0]) }
        indexed.sort { $0.1 > $1.1 }
        let kept = Set(indexed.prefix(maxPoints).map { $0.0 })
        return (0..<n).filter { kept.contains($0) }.map { coords[$0] }
    }

    /// Persist a completed journey immediately and ensure list order is updated.
    /// (Legacy call sites; prefer JourneyFinalizer + flushPersist)
    func addCompletedJourney(_ journey: JourneyRoute) {
        if let i = journeys.firstIndex(where: { $0.id == journey.id }) {
            journeys[i] = journey
        } else {
            journeys.insert(journey, at: 0)
        }
        bumpTrackTileRevision()
        GlobeRefreshCoordinator.shared.requestRefresh(reason: .journeySaved)
        flushPersist(journey: journey, force: true)
        syncCompletedJourneyIfNeeded(journey)
    }

    /// Apply many completed-journey updates in one pass to avoid UI stalls.
    func applyBulkCompletedUpdates(_ updates: [JourneyRoute]) {
        guard !updates.isEmpty else { return }

        let updateByID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        for idx in journeys.indices {
            let id = journeys[idx].id
            if let updated = updateByID[id] {
                journeys[idx] = updated
            }
        }

        if let oid = latestOngoing?.id, let updated = updateByID[oid], updated.endTime != nil {
            latestOngoing = nil
        }

        let snapshots = journeys
        bumpTrackTileRevision()
        updates
            .filter { $0.endTime != nil }
            .forEach(syncCompletedJourneyIfNeeded)

        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                for route in updates {
                    try self.fileStore.finalizeJourney(route)
                }
                try self.indexStore.replaceIDs(snapshots.map(\.id))
            } catch {
                print("❌ bulk completed update failed:", error)
            }
        }
    }

    /// File modification date of the most recently written journey file on disk.
    func lastPersistedAt(journeyID: String) -> Date? {
        fileStore.lastPersistedAt(journeyID: journeyID)
    }

    /// Compatibility alias.
    func deleteJourney(id: String) {
        discardJourney(id: id)
    }

    func discardJourney(id: String) {
        discardJourneys(ids: [id])
    }

    func discardJourneys(ids: [String]) {
        let uniqueIDs = Array(Set(ids.filter { !$0.isEmpty }))
        guard !uniqueIDs.isEmpty else { return }

        pendingMetaPersist?.cancel()
        pendingMetaPersist = nil

        let idSet = Set(uniqueIDs)
        journeys.removeAll(where: { idSet.contains($0.id) })
        if let ongoingID = latestOngoing?.id, idSet.contains(ongoingID) {
            latestOngoing = nil
        }

        if let currentID = currentPersistJourneyId, idSet.contains(currentID) {
            currentPersistJourneyId = nil
            lastSeenCoordCount = 0
            lastDeltaPersistCoordCount = 0
            lastDeltaPersistAt = .distantPast
        }
        bumpTrackTileRevision()

        NotificationCenter.default.post(
            name: .journeyStoreDidDiscardJourneys,
            object: self,
            userInfo: ["ids": uniqueIDs]
        )
        DeletedJourneyStore.record(uniqueIDs, userID: userID)
        uniqueIDs.forEach { syncHooks.deleteJourney?($0) }

        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                for id in uniqueIDs {
                    try self.fileStore.deleteJourney(id: id)
                    try self.indexStore.removeID(id)
                }
            } catch {
                print("❌ discard journeys failed:", error)
            }
        }
    }

    func mergeCloudSnapshots(upserts: [JourneyRoute], deletedIDs: [String]) {
        let deletedSet = Set(deletedIDs.filter { !$0.isEmpty })
        if !deletedSet.isEmpty {
            journeys.removeAll(where: { deletedSet.contains($0.id) })
            if let ongoingID = latestOngoing?.id, deletedSet.contains(ongoingID) {
                latestOngoing = nil
            }
        }

        for route in upserts {
            if let index = journeys.firstIndex(where: { $0.id == route.id }) {
                journeys[index] = route
            } else {
                journeys.insert(route, at: 0)
            }
        }

        guard !upserts.isEmpty || !deletedSet.isEmpty else { return }

        let snapshots = journeys
        bumpTrackTileRevision()

        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Index first: ensures no journey file becomes an invisible orphan on crash.
                try self.indexStore.replaceIDs(snapshots.map(\.id))
                for id in deletedSet {
                    try? self.fileStore.deleteJourney(id: id)
                }
                for route in upserts {
                    try self.fileStore.finalizeJourney(route)
                }
            } catch {
                print("❌ merge cloud snapshots failed:", error)
            }
        }
    }

    private var recentlySyncedIDs: [String: Date] = [:]
    private let syncDedupWindow: TimeInterval = 30

    private func syncCompletedJourneyIfNeeded(_ journey: JourneyRoute) {
        guard journey.endTime != nil else { return }
        let now = Date()
        if let lastSync = recentlySyncedIDs[journey.id],
           now.timeIntervalSince(lastSync) < syncDedupWindow {
            return
        }
        recentlySyncedIDs[journey.id] = now
        syncHooks.upsertCompletedJourney?(journey)
    }

    func trackRenderEvents() -> [TrackRenderEvent] {
        Self.makeTrackRenderEvents(from: journeys)
    }

    func trackRenderEventsAsync() async -> [TrackRenderEvent] {
        let snapshot = journeys
        return await Task.detached(priority: .utility) {
            Self.makeTrackRenderEvents(from: snapshot)
        }.value
    }

    private nonisolated static func makeTrackRenderEvents(from journeys: [JourneyRoute]) -> [TrackRenderEvent] {
        var out: [TrackRenderEvent] = []
        out.reserveCapacity(journeys.reduce(0) { $0 + $1.displayRouteCoordinates.count })

        for journey in journeys {
            // Ongoing journeys (endTime == nil) must NOT enter the tile system.
            // They have no valid time range, so all coords collapse to startTime
            // causing massive data to pile on one day and crash lifelog rendering.
            guard journey.endTime != nil else { continue }
            let coords = journey.displayRouteCoordinates
            guard !coords.isEmpty else { continue }
            guard let (start, end) = Self.resolveRenderRange(for: journey) else { continue }
            let span = max(0, end.timeIntervalSince(start))
            let denom = max(1, coords.count - 1)

            for (index, coord) in coords.enumerated() {
                let ts = start.addingTimeInterval(span * Double(index) / Double(denom))
                out.append(
                    TrackRenderEvent(
                        sourceType: .journey,
                        timestamp: ts,
                        coordinate: coord
                    )
                )
            }
        }
        return out
    }

    nonisolated static func resolveRenderRange(for journey: JourneyRoute) -> (Date, Date)? {
        if let start = journey.startTime, let end = journey.endTime {
            return start <= end ? (start, end) : (end, start)
        }
        if let start = journey.startTime {
            return (start, start)
        }
        if let end = journey.endTime {
            return (end, end)
        }
        if let earliest = journey.memories.map(\.timestamp).min(),
           let latest = journey.memories.map(\.timestamp).max() {
            return earliest <= latest ? (earliest, latest) : (latest, earliest)
        }
        return nil
    }

    private func bumpTrackTileRevision() {
        trackTileRevision &+= 1
        NotificationCenter.default.post(
            name: .journeyStoreTrackTilesDidChange,
            object: self,
            userInfo: ["revision": trackTileRevision]
        )
    }
}

// MARK: - Thumbnails

extension JourneyRoute {
    /// Ensures `thumbnailCoordinates` is populated with a downsampled polyline so overview UIs
    /// don't fall back to full `coordinates` for rendering.
    mutating func ensureThumbnail(maxPoints: Int) {
        guard maxPoints >= 2 else { return }

        if !thumbnailCoordinates.isEmpty {
            // If thumbnail is already reasonably sized, keep it.
            if thumbnailCoordinates.count <= maxPoints { return }
        }

        guard !coordinates.isEmpty else {
            thumbnailCoordinates = []
            return
        }

        if coordinates.count <= maxPoints {
            thumbnailCoordinates = coordinates
            return
        }

        // Evenly sample indices across the full route.
        let n = coordinates.count
        let m = maxPoints
        var out: [CoordinateCodable] = []
        out.reserveCapacity(m)

        for i in 0..<m {
            let t = Double(i) / Double(m - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coordinates[min(max(idx, 0), n - 1)])
        }

        // Remove consecutive duplicates (common when GPS noise is filtered).
        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(out.count)
        for c in out {
            if let last = compact.last, last.lat == c.lat, last.lon == c.lon {
                continue
            }
            compact.append(c)
        }
        thumbnailCoordinates = compact
    }
}
