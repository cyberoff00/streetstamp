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

    private var journeyStore: JourneyStore?
    private var lifelogStore: LifelogStore?
    private var trackTileStore: TrackTileStore?

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

    func bind(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore
    ) {
        self.journeyStore = journeyStore
        self.lifelogStore = lifelogStore
        self.trackTileStore = trackTileStore
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
        if let fallback = bestExistingSnapshot(for: key.day, countryISO2: key.countryISO2) {
            debugLog(
                "cached fallback day snapshot hit day=\(debugDayString(key.day)) " +
                "requested=(j:\(key.journeyRevision),p:\(key.lifelogRevision)) " +
                "existing=(j:\(fallback.key.journeyRevision),p:\(fallback.key.lifelogRevision))"
            )
            return fallback.renderSnapshot(in: viewport)
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
            "far=\(snapshot.farRouteSegments.count) footprints=\(snapshot.footprintRuns.count)"
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
            let manifest = trackTileStore.currentManifest
            debugLog(
                "day snapshot blocked day=\(debugDayString(key.day)) " +
                "requested=(j:\(key.journeyRevision),p:\(key.lifelogRevision)) " +
                "manifest=\(debugManifestString(manifest))"
            )
            return nil
        }
        let existing = bestExistingSnapshot(for: key.day, countryISO2: key.countryISO2)
        let task = Task<LifelogSegmentedDaySnapshot?, Never>(priority: .utility) {
            let segments = trackTileStore.tiles(
                for: nil,
                zoom: TrackRenderAdapter.unifiedRenderZoom,
                day: key.day
            )
            guard !segments.isEmpty else {
                await MainActor.run {
                    self.debugLog("day snapshot empty tiles day=\(self.debugDayString(key.day))")
                }
                return nil
            }
            await MainActor.run {
                self.debugLog(
                    "day snapshot build day=\(self.debugDayString(key.day)) " +
                    "segments=\(segments.count) existing=\(existing != nil)"
                )
            }
            return await Task.detached(priority: .utility) {
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
            }.value
        }
        inFlightDayTasks[key] = task
        let snapshot = await task.value
        inFlightDayTasks[key] = nil

        guard let snapshot else { return nil }
        debugLog(
            "day snapshot ready day=\(debugDayString(key.day)) " +
            "groups=\(snapshot.farRouteGroups.count)/\(snapshot.footprintGroups.count)"
        )
        pruneOlderDaySnapshots(for: key)
        daySnapshots[key] = snapshot
        trimDayCache(anchorDay: key.day)
        return snapshot
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
        warmupTask = Task(priority: .background) { [weak self] in
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
}

#if DEBUG
extension LifelogRenderCacheCoordinator {
    func seedDaySnapshotForTesting(_ snapshot: LifelogSegmentedDaySnapshot) {
        daySnapshots[snapshot.key] = snapshot
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
