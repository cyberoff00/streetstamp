import Foundation
import CoreLocation
import Combine

extension Notification.Name {
    static let lifelogCountryAttributionDidChange = Notification.Name("lifelogCountryAttributionDidChange")
}

@MainActor
final class LifelogRenderCacheCoordinator: ObservableObject {
    private static let recentDayCount = 7
    private static let viewportCacheLimit = 24
    private static let todayRefreshDelayNanoseconds: UInt64 = 5_000_000_000
    private static let diskCacheFilename = "lifelog_render_snapshot_cache.json"

    private var journeyStore: JourneyStore?
    private var lifelogStore: LifelogStore?
    private var trackTileStore: TrackTileStore?
    private var diskCacheURL: URL?

    private var daySnapshots: [LifelogDaySnapshotKey: LifelogSegmentedDaySnapshot] = [:]
    private var viewportSnapshots: [LifelogViewportRenderKey: LifelogRenderSnapshot] = [:]
    private var viewportLRU: [LifelogViewportRenderKey] = []

    private var inFlightDayTasks: [LifelogDaySnapshotKey: Task<LifelogSegmentedDaySnapshot?, Never>] = [:]
    private var inFlightViewportTasks: [LifelogViewportRenderKey: Task<LifelogRenderSnapshot?, Never>] = [:]

    private var warmupTask: Task<Void, Never>?
    private var todayRefreshTask: Task<Void, Never>?
    private var pendingWarmupRequest: (anchorDay: Date, countryISO2: String?)?
    private var hasDirtyToday = false
    private var todayDirtyCountryISO2: String?
    /// Snapshots restored from disk during bind(), keyed by startOfDay.
    /// Covers up to `recentDayCount` days so cold starts after the first one
    /// can serve any recent day immediately, not just today.
    private var restoredDiskSnapshots: [Date: LifelogRenderSnapshot] = [:]

    func bind(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        cachesDir: URL? = nil
    ) {
        self.journeyStore = journeyStore
        self.lifelogStore = lifelogStore
        self.trackTileStore = trackTileStore
        if let cachesDir {
            self.diskCacheURL = cachesDir.appendingPathComponent(Self.diskCacheFilename)
            restoreFromDisk()
        }
    }

    func reset() {
        warmupTask?.cancel()
        warmupTask = nil
        todayRefreshTask?.cancel()
        todayRefreshTask = nil
        hasDirtyToday = false
        todayDirtyCountryISO2 = nil
        pendingWarmupRequest = nil
        daySnapshots.removeAll(keepingCapacity: true)
        viewportSnapshots.removeAll(keepingCapacity: true)
        viewportLRU.removeAll(keepingCapacity: true)
        inFlightDayTasks.values.forEach { $0.cancel() }
        inFlightViewportTasks.values.forEach { $0.cancel() }
        inFlightDayTasks.removeAll(keepingCapacity: true)
        inFlightViewportTasks.removeAll(keepingCapacity: true)
    }

    func cachedRenderSnapshot(
        day: Date?,
        countryISO2: String?,
        viewport: TrackTileViewport?
    ) -> LifelogRenderSnapshot? {
        guard let key = currentDayKey(day: day, countryISO2: countryISO2) else { return nil }
        return cachedRenderSnapshot(for: key, viewport: viewport)
    }

    private func cachedRenderSnapshot(
        for key: LifelogDaySnapshotKey,
        viewport: TrackTileViewport?
    ) -> LifelogRenderSnapshot? {
        let viewportKey = LifelogViewportRenderKey(
            dayKey: key,
            viewportBucket: LifelogViewportBucket.bucket(for: viewport)
        )
        if let cached = viewportSnapshots[viewportKey] {
            touchViewportKey(viewportKey)
            return cached
        }

        if let exact = daySnapshots[key] {
            debugLog("cached day snapshot hit day=\(debugDayString(key.day)) j=\(key.journeyRevision) p=\(key.lifelogRevision)")
            return exact.renderSnapshot(in: viewport)
        }
        if !Calendar.current.isDateInToday(key.day),
           let fallback = bestExistingSnapshot(for: key.day, countryISO2: key.countryISO2) {
            debugLog(
                "cached fallback day snapshot hit day=\(debugDayString(key.day)) " +
                "requested=(j:\(key.journeyRevision),p:\(key.lifelogRevision)) " +
                "existing=(j:\(fallback.key.journeyRevision),p:\(fallback.key.lifelogRevision))"
            )
            return fallback.renderSnapshot(in: viewport)
        }
        let dayKey = Calendar.current.startOfDay(for: key.day)
        if let restored = restoredDiskSnapshots[dayKey] {
            debugLog("disk cache hit day=\(debugDayString(key.day))")
            return restored
        }
        debugLog("cache miss day=\(debugDayString(key.day)) j=\(key.journeyRevision) p=\(key.lifelogRevision)")
        return nil
    }

    func ensureRenderSnapshot(
        day: Date?,
        countryISO2: String?,
        viewport: TrackTileViewport?
    ) async -> LifelogRenderSnapshot? {
        warmupTask?.cancel()
        warmupTask = nil

        guard let key = currentDayKey(day: day, countryISO2: countryISO2) else { return nil }
        debugLog("ensure render snapshot day=\(debugDayString(key.day)) j=\(key.journeyRevision) p=\(key.lifelogRevision)")
        guard let daySnapshot = await ensureDaySnapshot(for: key) else { return nil }

        let viewportKey = LifelogViewportRenderKey(
            dayKey: key,
            viewportBucket: LifelogViewportBucket.bucket(for: viewport)
        )
        if let cached = viewportSnapshots[viewportKey] {
            touchViewportKey(viewportKey)
            return cached
        }

        if viewport == nil {
            return daySnapshot.allDayRenderSnapshot
        }

        if let inFlight = inFlightViewportTasks[viewportKey] {
            return await inFlight.value
        }

        let request = LifelogRenderSnapshotRequest.viewportRender(
            selectedDay: key.day,
            countryISO2: key.countryISO2
        )
        let task = Task<LifelogRenderSnapshot?, Never>(priority: .utility) {
            await Task.detached(priority: .utility) {
                LifelogRenderSnapshotBuilder.buildViewportSnapshot(
                    daySnapshot: daySnapshot,
                    request: request,
                    viewport: viewport
                )
            }.value
        }
        inFlightViewportTasks[viewportKey] = task
        let snapshot = await task.value
        inFlightViewportTasks[viewportKey] = nil

        guard let snapshot else { return nil }
        debugLog(
            "viewport snapshot ready day=\(debugDayString(key.day)) " +
            "far=\(snapshot.farRouteSegments.count)"
        )
        viewportSnapshots[viewportKey] = snapshot
        touchViewportKey(viewportKey)
        trimViewportCacheIfNeeded()
        return snapshot
    }

    func scheduleWarmupRecentDays(anchorDay: Date = Date(), countryISO2: String?) {
        pendingWarmupRequest = (
            anchorDay: Calendar.current.startOfDay(for: anchorDay),
            countryISO2: countryISO2
        )
        launchPendingWarmupIfPossible()
    }

    func noteTrackTileRefresh(countryISO2: String?) {
        if let pending = pendingWarmupRequest {
            pendingWarmupRequest = (
                anchorDay: pending.anchorDay,
                countryISO2: countryISO2 ?? pending.countryISO2
            )
            launchPendingWarmupIfPossible()
        }
        guard hasDirtyToday else { return }
        guard todayRefreshTask == nil else { return }
        scheduleTodayRefresh(countryISO2: countryISO2, delayNanoseconds: 0)
    }

    func noteCountryAttributionRefresh(countryISO2: String?) {
        invalidateDaySnapshots(day: Date())
        markTodayDirty(countryISO2: countryISO2)
        scheduleWarmupRecentDays(anchorDay: Date(), countryISO2: countryISO2)
    }

    func markTodayDirty(countryISO2: String?) {
        invalidateDaySnapshots(day: Date())
        restoredDiskSnapshots[Calendar.current.startOfDay(for: Date())] = nil
        hasDirtyToday = true
        todayDirtyCountryISO2 = countryISO2
        guard todayRefreshTask == nil else { return }
        scheduleTodayRefresh(
            countryISO2: countryISO2,
            delayNanoseconds: Self.todayRefreshDelayNanoseconds
        )
    }

    private func scheduleTodayRefresh(countryISO2: String?, delayNanoseconds: UInt64) {
        todayRefreshTask = Task(priority: .utility) { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            await self?.runTodayRefresh(countryISO2: countryISO2)
        }
    }

    private func runTodayRefresh(countryISO2: String?) async {
        todayRefreshTask = nil
        guard hasDirtyToday else { return }
        let targetCountry = countryISO2 ?? todayDirtyCountryISO2
        guard let key = currentDayKey(day: Date(), countryISO2: targetCountry) else { return }
        guard await ensureDaySnapshot(for: key) != nil else { return }
        hasDirtyToday = false
        todayDirtyCountryISO2 = targetCountry
    }

    private func currentDayKey(day: Date?, countryISO2: String?) -> LifelogDaySnapshotKey? {
        guard let journeyStore, let lifelogStore else { return nil }
        let resolvedDay = Calendar.current.startOfDay(for: day ?? Date())
        return LifelogDaySnapshotKey(
            day: resolvedDay,
            countryISO2: countryISO2,
            journeyRevision: journeyStore.trackTileRevision,
            lifelogRevision: lifelogStore.trackTileRevision
        )
    }

    private func ensureDaySnapshot(for key: LifelogDaySnapshotKey?) async -> LifelogSegmentedDaySnapshot? {
        guard let key else { return nil }
        if let cached = daySnapshots[key] {
            debugLog("day snapshot exact hit day=\(debugDayString(key.day)) j=\(key.journeyRevision) p=\(key.lifelogRevision)")
            return cached
        }
        if let inFlight = inFlightDayTasks[key] {
            debugLog("day snapshot in-flight reuse day=\(debugDayString(key.day))")
            return await inFlight.value
        }

        guard let trackTileStore else { return nil }
        guard let manifest = trackTileStore.currentManifest,
              manifest.zoom == TrackRenderAdapter.unifiedRenderZoom,
              manifest.journeyRevision >= key.journeyRevision,
              manifest.passiveRevision >= key.lifelogRevision else {
            // Track tiles not ready yet — build a quick fallback snapshot
            // from raw lifelog shard data so the user sees content immediately
            // on cold start instead of an empty map.
            let manifest = trackTileStore.currentManifest
            debugLog(
                "day snapshot tiles not ready day=\(debugDayString(key.day)) " +
                "requested=(j:\(key.journeyRevision),p:\(key.lifelogRevision)) " +
                "manifest=\(debugManifestString(manifest)) → fallback from raw points"
            )
            return buildFallbackFromRawPoints(for: key)
        }
        let existing = bestExistingSnapshot(for: key.day, countryISO2: key.countryISO2)
        // Single Task.detached: tile lookup + builder run in one off-main hop.
        // Was previously a Task wrapping a Task.detached; the outer hop served
        // no purpose since the inner detached call ran nonisolated builder code.
        let task = Task<LifelogSegmentedDaySnapshot?, Never>.detached(priority: .userInitiated) { [trackTileStore] in
            let segments = trackTileStore.tiles(
                for: nil,
                zoom: TrackRenderAdapter.unifiedRenderZoom,
                day: key.day
            )
            guard !segments.isEmpty else { return nil }
            if let existing {
                return LifelogRenderSnapshotBuilder.mergeDaySnapshot(
                    existing: existing,
                    latestKey: key,
                    latestSegments: segments
                )
            }
            return LifelogRenderSnapshotBuilder.buildDaySnapshot(
                key: key,
                segments: segments
            )
        }
        inFlightDayTasks[key] = task
        let snapshot = await task.value
        inFlightDayTasks[key] = nil

        guard let snapshot else { return nil }
        debugLog(
            "day snapshot ready day=\(debugDayString(key.day)) " +
            "groups=\(snapshot.farRouteGroups.count)"
        )
        pruneOlderDaySnapshots(for: key)
        daySnapshots[key] = snapshot
        trimDayCache(anchorDay: key.day)
        // Persist any recent-day snapshot so cold starts beyond the first
        // serve all 7 days from disk immediately. The disk file is rewritten
        // with the current in-memory recent-day set (small JSON, off main).
        let dayKey = Calendar.current.startOfDay(for: key.day)
        let recentDays = Set(LifelogRenderWarmupPlanner.recentDays(
            anchorDay: Date(),
            count: Self.recentDayCount
        ).map { Calendar.current.startOfDay(for: $0) })
        if recentDays.contains(dayKey) {
            restoredDiskSnapshots[dayKey] = nil
            saveRecentDaysToDisk()
        }
        return snapshot
    }

    /// Build a lightweight render snapshot directly from raw lifelog shard
    /// coordinates, bypassing the track tile system.  Used as a cold-start
    /// fallback so the user sees today's route immediately while tiles build
    /// in the background.  The snapshot is NOT cached in `daySnapshots` —
    /// once tiles are ready the normal path will produce a proper snapshot
    /// that replaces it.
    private func buildFallbackFromRawPoints(for key: LifelogDaySnapshotKey) -> LifelogSegmentedDaySnapshot? {
        guard let lifelogStore else { return nil }
        // Use sorted variant: journey-archived points may be appended out of
        // chronological order in today's shard, which causes a transient line
        // connecting distant route sections when rendered as a single segment.
        let rawCoords = lifelogStore.rawCoordsSortedForDay(key.day)
        guard rawCoords.count >= 2 else { return nil }
        let segment = TrackTileSegment(
            sourceType: .passive,
            coordinates: rawCoords
        )
        return LifelogRenderSnapshotBuilder.buildDaySnapshot(
            key: key,
            segments: [segment]
        )
    }

    private func bestExistingSnapshot(for day: Date, countryISO2: String?) -> LifelogSegmentedDaySnapshot? {
        let targetDay = Calendar.current.startOfDay(for: day)
        return daySnapshots
            .filter { entry in
                entry.key.day == targetDay && entry.key.countryISO2 == normalizedISO2(countryISO2)
            }
            .sorted { lhs, rhs in
                if lhs.key.journeyRevision != rhs.key.journeyRevision {
                    return lhs.key.journeyRevision > rhs.key.journeyRevision
                }
                return lhs.key.lifelogRevision > rhs.key.lifelogRevision
            }
            .first?
            .value
    }

    private func trimDayCache(anchorDay: Date) {
        let allowedDays = Set(
            LifelogRenderWarmupPlanner.recentDays(
                anchorDay: anchorDay,
                count: Self.recentDayCount
            )
            .map { Calendar.current.startOfDay(for: $0) }
        )

        daySnapshots = daySnapshots.filter { allowedDays.contains($0.key.day) }
        viewportSnapshots = viewportSnapshots.filter { allowedDays.contains($0.key.dayKey.day) }
        viewportLRU.removeAll { key in
            !allowedDays.contains(key.dayKey.day) || viewportSnapshots[key] == nil
        }
    }

    private func pruneOlderDaySnapshots(for key: LifelogDaySnapshotKey) {
        daySnapshots = daySnapshots.filter { entry in
            !(entry.key.day == key.day &&
              entry.key.countryISO2 == key.countryISO2 &&
              entry.key != key)
        }
        viewportSnapshots = viewportSnapshots.filter { entry in
            !(entry.key.dayKey.day == key.day &&
              entry.key.dayKey.countryISO2 == key.countryISO2 &&
              entry.key.dayKey != key)
        }
        viewportLRU.removeAll { viewportKey in
            viewportKey.dayKey.day == key.day &&
            viewportKey.dayKey.countryISO2 == key.countryISO2 &&
            viewportKey.dayKey != key
        }
    }

    private func touchViewportKey(_ key: LifelogViewportRenderKey) {
        viewportLRU.removeAll { $0 == key }
        viewportLRU.append(key)
    }

    private func trimViewportCacheIfNeeded() {
        while viewportLRU.count > Self.viewportCacheLimit {
            let removed = viewportLRU.removeFirst()
            viewportSnapshots.removeValue(forKey: removed)
        }
    }

    private func invalidateDaySnapshots(day: Date) {
        let targetDay = Calendar.current.startOfDay(for: day)
        let removedKeys = Set(
            daySnapshots.keys.filter { Calendar.current.isDate($0.day, inSameDayAs: targetDay) }
        )
        guard !removedKeys.isEmpty else { return }

        daySnapshots = daySnapshots.filter { !removedKeys.contains($0.key) }
        viewportSnapshots = viewportSnapshots.filter { !removedKeys.contains($0.key.dayKey) }
        viewportLRU.removeAll { removedKeys.contains($0.dayKey) }
        removedKeys.forEach { key in
            inFlightDayTasks[key]?.cancel()
            inFlightDayTasks.removeValue(forKey: key)
        }
        let viewportKeys = inFlightViewportTasks.keys.filter { removedKeys.contains($0.dayKey) }
        viewportKeys.forEach { key in
            inFlightViewportTasks[key]?.cancel()
            inFlightViewportTasks.removeValue(forKey: key)
        }
    }

    private func launchPendingWarmupIfPossible() {
        guard let request = pendingWarmupRequest else { return }
        guard let trackTileStore else { return }
        guard let manifest = trackTileStore.currentManifest,
              manifest.zoom == TrackRenderAdapter.unifiedRenderZoom else {
            return
        }

        pendingWarmupRequest = nil
        warmupTask?.cancel()

        let days = LifelogRenderWarmupPlanner.recentDays(
            anchorDay: request.anchorDay,
            count: Self.recentDayCount
        )
        // .userInitiated so the splash-window warmup is not throttled by the
        // OS the way .background is. The caller (cold-start Phase 2) waits on
        // this so user-perceptible latency depends on it completing before
        // the user reaches LifelogView.
        warmupTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for day in days {
                guard !Task.isCancelled else { return }
                let key = await self.currentDayKey(day: day, countryISO2: request.countryISO2)
                _ = await self.ensureDaySnapshot(for: key)
            }
        }
    }

    private func normalizedISO2(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let iso = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.isEmpty ? nil : iso
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("🧭 [LifelogRenderCache] \(message)")
#endif
    }

    private func debugDayString(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    private func debugManifestString(_ manifest: TrackTileManifest?) -> String {
        guard let manifest else { return "nil" }
        return "(zoom:\(manifest.zoom),j:\(manifest.journeyRevision),p:\(manifest.passiveRevision))"
    }

    // MARK: - Disk cache for cold-start restore

    private func restoreFromDisk() {
        guard let url = diskCacheURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let allowedDays = Set(LifelogRenderWarmupPlanner.recentDays(
            anchorDay: Date(),
            count: Self.recentDayCount
        ).map { Calendar.current.startOfDay(for: $0) })
        do {
            let data = try Data(contentsOf: url)
            // V2 (multi-day) first; fall back to legacy V1 (single today snapshot).
            if let cachedV2 = try? JSONDecoder.iso8601Lifelog.decode(LifelogRenderSnapshotDiskCacheV2.self, from: data),
               cachedV2.version >= 2 {
                for entry in cachedV2.snapshots {
                    let snapshot = entry.toRenderSnapshot()
                    guard let day = snapshot.selectedDay else { continue }
                    let dayKey = Calendar.current.startOfDay(for: day)
                    guard allowedDays.contains(dayKey) else { continue }
                    restoredDiskSnapshots[dayKey] = snapshot
                }
                debugLog("disk cache v2 restored days=\(restoredDiskSnapshots.count)")
                return
            }
            let cached = try JSONDecoder.iso8601Lifelog.decode(LifelogRenderSnapshotDiskCache.self, from: data)
            let snapshot = cached.toRenderSnapshot()
            guard let day = snapshot.selectedDay,
                  Calendar.current.isDateInToday(day) else {
                debugLog("disk cache stale, discarding")
                try? FileManager.default.removeItem(at: url)
                return
            }
            restoredDiskSnapshots[Calendar.current.startOfDay(for: day)] = snapshot
            debugLog("disk cache v1 restored day=\(debugDayString(day)) far=\(snapshot.farRouteSegments.count)")
        } catch {
            debugLog("disk cache restore failed: \(error)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func saveRecentDaysToDisk() {
        guard let url = diskCacheURL else { return }
        let recentDays = Set(LifelogRenderWarmupPlanner.recentDays(
            anchorDay: Date(),
            count: Self.recentDayCount
        ).map { Calendar.current.startOfDay(for: $0) })
        // Snapshot in-memory entries on the main actor before hopping off,
        // so the encode never touches mutable shared state.
        let snapshots: [LifelogRenderSnapshot] = daySnapshots
            .filter { recentDays.contains($0.key.day) }
            .map { $0.value.allDayRenderSnapshot }
        guard !snapshots.isEmpty else { return }
        Task.detached(priority: .utility) {
            do {
                let cached = LifelogRenderSnapshotDiskCacheV2(snapshots: snapshots)
                let data = try JSONEncoder.iso8601Lifelog.encode(cached)
                try data.write(to: url, options: .atomic)
            } catch {
                // Best-effort; failure is not critical.
            }
        }
    }
}

// MARK: - Codable disk cache format

/// V2: multi-day disk cache. Each cold start can restore up to
/// `recentDayCount` days, so users land on any recent day instantly
/// rather than waiting for the warmup task to rebuild it.
private struct LifelogRenderSnapshotDiskCacheV2: Codable {
    let version: Int
    let snapshots: [LifelogRenderSnapshotDiskCache]

    init(snapshots: [LifelogRenderSnapshot]) {
        self.version = 2
        self.snapshots = snapshots.map { LifelogRenderSnapshotDiskCache(from: $0) }
    }
}

private struct LifelogRenderSnapshotDiskCache: Codable {
    struct Coord: Codable {
        let lat: Double
        let lon: Double
    }
    struct Segment: Codable {
        let id: String
        let style: String
        let coords: [Coord]
    }

    let selectedDay: Date?
    let farRouteSegments: [Segment]
    let centerLat: Double?
    let centerLon: Double?

    init(from snapshot: LifelogRenderSnapshot) {
        self.selectedDay = snapshot.selectedDay
        self.farRouteSegments = snapshot.farRouteSegments.map { seg in
            Segment(
                id: seg.id,
                style: seg.style.rawValue,
                coords: seg.coords.map { Coord(lat: $0.latitude, lon: $0.longitude) }
            )
        }
        self.centerLat = snapshot.selectedDayCenterCoordinate?.latitude
        self.centerLon = snapshot.selectedDayCenterCoordinate?.longitude
    }

    func toRenderSnapshot() -> LifelogRenderSnapshot {
        let center: CLLocationCoordinate2D?
        if let lat = centerLat, let lon = centerLon {
            center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            center = nil
        }
        return LifelogRenderSnapshot(
            selectedDay: selectedDay,
            cachedPathCoordsWGS84: [],
            farRouteSegments: farRouteSegments.map { seg in
                RenderRouteSegment(
                    id: seg.id,
                    style: RenderRouteSegment.Style(rawValue: seg.style) ?? .solid,
                    coords: seg.coords.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    }
                )
            },
            selectedDayCenterCoordinate: center,
            isHighQuality: false
        )
    }
}

private extension JSONEncoder {
    static let iso8601Lifelog: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601Lifelog: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

#if DEBUG
extension LifelogRenderCacheCoordinator {
    func seedDaySnapshotForTesting(_ snapshot: LifelogSegmentedDaySnapshot) {
        daySnapshots[snapshot.key] = snapshot
    }

    func cachedRenderSnapshotForTesting(
        key: LifelogDaySnapshotKey,
        viewport: TrackTileViewport?
    ) -> LifelogRenderSnapshot? {
        cachedRenderSnapshot(for: key, viewport: viewport)
    }

    func hasCachedDaySnapshotForTesting(_ key: LifelogDaySnapshotKey) -> Bool {
        daySnapshots[key] != nil
    }

    var pendingWarmupRequestForTesting: (anchorDay: Date, countryISO2: String?)? {
        pendingWarmupRequest
    }

    var todayDirtyCountryISO2ForTesting: String? {
        todayDirtyCountryISO2
    }

    var hasDirtyTodayForTesting: Bool {
        hasDirtyToday
    }
}
#endif
