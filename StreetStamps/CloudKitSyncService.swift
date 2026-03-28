import CloudKit
import Foundation

// MARK: - Record Types

enum CloudKitRecordType {
    static let journey = "Journey"
    static let journeyMemory = "JourneyMemory"
    static let photo = "Photo"
    static let passiveLifelogBatch = "PassiveLifelogBatch"
    static let lifelogMood = "LifelogMood"
    static let settings = "Settings"
    @available(*, deprecated, message: "Use passiveLifelogBatch for the new incremental sync path.")
    static let lifelogBatch = passiveLifelogBatch
    @available(*, deprecated, message: "City cache is not a primary sync domain in the new incremental sync path.")
    static let cityCache = "CityCache"
}

struct CloudKitRestoreResult {
    var restoredJourneyCount: Int = 0
    var restoredLifelogCount: Int = 0
    var restoredSettingsCount: Int = 0
    var restoredPhotoCount: Int = 0

    var journeyFailed: Bool = false
    var lifelogFailed: Bool = false
    var settingsFailed: Bool = false
    var photoFailed: Bool = false

    var totalCount: Int {
        restoredJourneyCount + restoredLifelogCount + restoredSettingsCount + restoredPhotoCount
    }

    var hasAnyFailure: Bool {
        journeyFailed || lifelogFailed || settingsFailed || photoFailed
    }
}

struct CloudKitStatusSnapshot: Equatable {
    let status: String?
    let at: Date?
}

// MARK: - Sync Coordinator

actor CloudKitSyncService {
    static let shared = CloudKitSyncService()
    private static let lastJourneySyncAtKeyPrefix = "streetstamps.cloudkit.journey.last_sync."
    private static let lastLifelogSyncAtKeyPrefix = "streetstamps.cloudkit.lifelog.last_sync."
    private static let lastMoodSyncAtKeyPrefix = "streetstamps.cloudkit.lifelog_mood.last_sync."
    private static let lastPhotoSyncAtKeyPrefix = "streetstamps.cloudkit.photo.last_sync."
    private static let statusKeyPrefix = "streetstamps.icloud.sync.status."
    private static let statusAtKeyPrefix = "streetstamps.icloud.sync.status_at."

    private let container: CKContainer
    private let database: CKDatabase
    private let journeySync: JourneyCloudKitSync
    private let lifelogSync: LifelogCloudKitSync
    private let lifelogMoodSync: LifelogMoodCloudKitSync
    private let photoSync: PhotoCloudKitSync
    private let settingsSync: SettingsCloudKitSync
    private let defaults: UserDefaults

    init(container: CKContainer = .default(), defaults: UserDefaults = .standard) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.journeySync = JourneyCloudKitSync(database: database)
        self.lifelogSync = LifelogCloudKitSync(database: database)
        self.lifelogMoodSync = LifelogMoodCloudKitSync(database: database)
        self.photoSync = PhotoCloudKitSync(database: database)
        self.settingsSync = SettingsCloudKitSync(database: database)
        self.defaults = defaults
    }

    func isAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    func ensureZones() async throws {
        try await journeySync.ensureZone()
        try await lifelogSync.ensureZone()
        try await lifelogMoodSync.ensureZone()
        try await photoSync.ensureZone()
        try await settingsSync.ensureZone()
    }

    // MARK: - Per-Entity Sync Hooks

    func syncJourneyUpsert(_ journey: JourneyRoute, localUserID: String? = nil) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAvailable() else { return }
        do {
            try await journeySync.ensureZone()
            try await journeySync.uploadJourney(journey)

            if let userID = localUserID {
                try await uploadPhotosForJourney(journey, localUserID: userID)
            }
        } catch {
            print("☁️ incremental journey upsert failed:", error)
        }
    }

    func syncJourneyDeletion(id: String) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAvailable() else { return }
        do {
            try await journeySync.ensureZone()
            try await journeySync.deleteJourney(id: id)
        } catch {
            print("☁️ incremental journey delete failed:", error)
        }
    }

    // MARK: - Batch Sync

    func syncCurrentState(
        userID: String,
        localUserID: String? = nil,
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        reason: String,
        forceFullJourneyUpload: Bool = false,
        forceFullLifelogUpload: Bool = false
    ) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAvailable() else { return }

        do {
            try await ensureZones()
            let didUploadJourneys = try await uploadJourneySnapshot(
                journeyStore: journeyStore,
                forceFull: forceFullJourneyUpload,
                localUserID: localUserID
            )
            let didUploadLifelog = try await uploadLifelogSnapshot(
                lifelogStore: lifelogStore,
                forceFull: forceFullLifelogUpload
            )
            let didUploadSettings = try await uploadSettingsSnapshot()

            guard didUploadJourneys || didUploadLifelog || didUploadSettings
                || forceFullJourneyUpload || forceFullLifelogUpload else {
                return
            }
            writeStatus(userID: userID, status: "upload_success")
            print("☁️ incremental iCloud sync uploaded (\(reason))")
        } catch {
            print("☁️ incremental iCloud sync failed:", error)
            writeStatus(userID: userID, status: "upload_failed")
        }
    }

    // MARK: - Journey Restore

    func restoreJourneySnapshot(
        into journeyStore: JourneyStore,
        userID: String,
        forceFull: Bool = false
    ) async -> Int {
        guard forceFull || AppSettings.isICloudSyncEnabled else { return 0 }
        guard await isAvailable() else { return 0 }

        do {
            try await journeySync.ensureZone()
            let markerKey = Self.lastJourneySyncAtKey(for: userID)
            let modifiedAfter = forceFull ? nil : (defaults.object(forKey: markerKey) as? Date)
            let snapshots = try await journeySync.downloadSnapshots(modifiedAfter: modifiedAfter)
            guard !snapshots.isEmpty else { return 0 }

            let upserts: [JourneyRoute] = snapshots.compactMap { snapshot in
                guard !snapshot.isDeleted else { return nil }
                return snapshot.journey
            }
            let deletedIDs = snapshots
                .filter(\.isDeleted)
                .map(\.journeyID)

            await MainActor.run {
                journeyStore.mergeCloudSnapshots(upserts: upserts, deletedIDs: deletedIDs)
            }

            if let newestSyncDate = snapshots.map(\.modifiedAt).max() {
                defaults.set(newestSyncDate, forKey: markerKey)
            }
            return upserts.count + deletedIDs.count
        } catch {
            print("☁️ restore incremental journeys failed:", error)
            return -1
        }
    }

    // MARK: - Lifelog Sync & Restore

    func syncLifelogSnapshot(_ lifelogStore: LifelogStore) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAvailable() else { return }
        do {
            try await lifelogSync.ensureZone()
            try await lifelogMoodSync.ensureZone()
            _ = try await uploadLifelogSnapshot(lifelogStore: lifelogStore, forceFull: false)
        } catch {
            print("☁️ incremental lifelog sync failed:", error)
        }
    }

    func restoreLifelogSnapshot(
        into lifelogStore: LifelogStore,
        userID: String,
        forceFull: Bool = false
    ) async -> Int {
        guard forceFull || AppSettings.isICloudSyncEnabled else { return 0 }
        guard await isAvailable() else { return 0 }
        do {
            try await lifelogSync.ensureZone()
            try await lifelogMoodSync.ensureZone()

            let dayMarkerKey = Self.lastLifelogSyncAtKey(for: userID)
            let moodMarkerKey = Self.lastMoodSyncAtKey(for: userID)
            let dayModifiedAfter = forceFull ? nil : (defaults.object(forKey: dayMarkerKey) as? Date)
            let moodModifiedAfter = forceFull ? nil : (defaults.object(forKey: moodMarkerKey) as? Date)

            let daySnapshots = try await lifelogSync.downloadSnapshots(modifiedAfter: dayModifiedAfter)
            let moodSnapshots = try await lifelogMoodSync.downloadSnapshots(modifiedAfter: moodModifiedAfter)
            guard !daySnapshots.isEmpty || !moodSnapshots.isEmpty else { return 0 }

            let dayBatches = daySnapshots.reduce(into: [String: [LifelogStore.LifelogTrackPoint]]()) { partial, snapshot in
                guard !snapshot.isDeleted else { return }
                partial[snapshot.dayKey] = snapshot.points
            }
            let deletedDayKeys = daySnapshots.filter(\.isDeleted).map(\.dayKey)
            let moodByDay = moodSnapshots.reduce(into: [String: String]()) { partial, snapshot in
                guard !snapshot.isDeleted, let mood = snapshot.mood else { return }
                partial[snapshot.dayKey] = mood
            }
            let deletedMoodDayKeys = moodSnapshots.filter(\.isDeleted).map(\.dayKey)

            await MainActor.run {
                lifelogStore.mergeCloudRestore(
                    dayBatches: dayBatches,
                    deletedDayKeys: deletedDayKeys,
                    moodByDay: moodByDay,
                    deletedMoodDayKeys: deletedMoodDayKeys
                )
            }

            if let newestDaySyncDate = daySnapshots.map(\.modifiedAt).max() {
                defaults.set(newestDaySyncDate, forKey: dayMarkerKey)
            }
            if let newestMoodSyncDate = moodSnapshots.map(\.modifiedAt).max() {
                defaults.set(newestMoodSyncDate, forKey: moodMarkerKey)
            }

            return dayBatches.count + moodByDay.count + deletedDayKeys.count + deletedMoodDayKeys.count
        } catch {
            print("☁️ restore incremental lifelog failed:", error)
            return -1
        }
    }

    // MARK: - Settings Restore

    func restoreSettingsSnapshot() async -> Int {
        guard AppSettings.isICloudSyncEnabled else { return 0 }
        guard await isAvailable() else { return 0 }
        do {
            try await settingsSync.ensureZone()
            guard let restored = try await settingsSync.downloadSettings() else { return 0 }
            for (key, value) in restored {
                if SettingsCloudKitSync.mergeOnRestoreKeys.contains(key) {
                    Self.mergeEconomyFromCloud(remoteValue: value, defaults: defaults)
                } else {
                    defaults.set(value, forKey: key)
                }
            }
            Self.propagateRestoredSettingsToUserScope(defaults: defaults)
            return restored.count
        } catch {
            print("☁️ restore settings failed:", error)
            return -1
        }
    }

    private static func propagateRestoredSettingsToUserScope(defaults: UserDefaults) {
        guard let userID = UserScopedProfileStateStore.activeLocalProfileID(defaults: defaults) else { return }
        if let loadoutData = defaults.data(forKey: UserScopedProfileStateStore.globalAvatarLoadoutKey) {
            defaults.set(loadoutData, forKey: UserScopedProfileStateStore.avatarLoadoutKey(for: userID))
        }
        if let economyData = defaults.data(forKey: UserScopedProfileStateStore.globalEconomyKey) {
            defaults.set(economyData, forKey: UserScopedProfileStateStore.economyKey(for: userID))
        }
    }

    private static func mergeEconomyFromCloud(remoteValue: Any, defaults: UserDefaults) {
        guard let remoteData = remoteValue as? Data,
              let remote = try? JSONDecoder().decode(EquipmentEconomy.self, from: remoteData) else {
            return
        }
        let key = UserScopedProfileStateStore.globalEconomyKey
        let local: EquipmentEconomy
        if let localData = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EquipmentEconomy.self, from: localData) {
            local = decoded
        } else {
            local = .empty
        }

        var merged = local
        merged.coins = max(local.coins, remote.coins)
        for (category, items) in remote.ownedItemsByCategory {
            let existing = Set(merged.ownedItemsByCategory[category] ?? [])
            let union = existing.union(items)
            merged.ownedItemsByCategory[category] = Array(union)
        }

        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: key)
            if let userID = UserScopedProfileStateStore.activeLocalProfileID(defaults: defaults) {
                defaults.set(data, forKey: UserScopedProfileStateStore.economyKey(for: userID))
            }
        }
    }

    // MARK: - Full Restore

    func restoreAllData(
        into journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        cityCache: CityCache? = nil,
        userID: String,
        localUserID: String? = nil,
        forceFull: Bool = false,
        writeManualStatus: Bool = false
    ) async -> CloudKitRestoreResult {
        guard forceFull || AppSettings.isICloudSyncEnabled else { return CloudKitRestoreResult() }
        guard await isAvailable() else {
            if writeManualStatus {
                writeStatus(userID: userID, status: "restore_failed")
            }
            return CloudKitRestoreResult()
        }

        var rawJourneyCount = await restoreJourneySnapshot(
            into: journeyStore,
            userID: userID,
            forceFull: forceFull
        )
        var rawLifelogCount = await restoreLifelogSnapshot(
            into: lifelogStore,
            userID: userID,
            forceFull: forceFull
        )
        var rawSettingsCount = await restoreSettingsSnapshot()
        var rawPhotoCount = await restorePhotos(
            localUserID: localUserID ?? userID,
            forceFull: forceFull
        )

        // Retry failed domains once after a short delay
        let failedDomains = (rawJourneyCount < 0, rawLifelogCount < 0, rawSettingsCount < 0, rawPhotoCount < 0)
        if failedDomains.0 || failedDomains.1 || failedDomains.2 || failedDomains.3 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if failedDomains.0 {
                let retry = await restoreJourneySnapshot(into: journeyStore, userID: userID, forceFull: forceFull)
                if retry >= 0 { rawJourneyCount = retry }
            }
            if failedDomains.1 {
                let retry = await restoreLifelogSnapshot(into: lifelogStore, userID: userID, forceFull: forceFull)
                if retry >= 0 { rawLifelogCount = retry }
            }
            if failedDomains.2 {
                let retry = await restoreSettingsSnapshot()
                if retry >= 0 { rawSettingsCount = retry }
            }
            if failedDomains.3 {
                let retry = await restorePhotos(localUserID: localUserID ?? userID, forceFull: forceFull)
                if retry >= 0 { rawPhotoCount = retry }
            }
        }

        let result = CloudKitRestoreResult(
            restoredJourneyCount: max(0, rawJourneyCount),
            restoredLifelogCount: max(0, rawLifelogCount),
            restoredSettingsCount: max(0, rawSettingsCount),
            restoredPhotoCount: max(0, rawPhotoCount),
            journeyFailed: rawJourneyCount < 0,
            lifelogFailed: rawLifelogCount < 0,
            settingsFailed: rawSettingsCount < 0,
            photoFailed: rawPhotoCount < 0
        )

        await MainActor.run {
            Self.rebuildDerivedCityStateIfNeeded(
                restoredJourneyCount: result.restoredJourneyCount,
                cityCache: cityCache
            )
        }

        if writeManualStatus {
            if result.hasAnyFailure {
                writeStatus(userID: userID, status: "restore_partial")
            } else if result.totalCount > 0 {
                writeStatus(userID: userID, status: "restore_success")
            } else {
                writeStatus(userID: userID, status: forceFull ? "no_backup" : "already_latest")
            }
        }

        return result
    }

    @MainActor
    static func rebuildDerivedCityStateIfNeeded(
        restoredJourneyCount: Int,
        cityCache: CityCache?
    ) {
        guard restoredJourneyCount > 0 else { return }
        cityCache?.rebuildFromJourneyStore()
    }

    // MARK: - Full Bidirectional Sync

    func syncAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async throws {
        guard await isAvailable() else { return }
        try await ensureZones()

        await downloadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)
        await uploadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)
    }

    private func downloadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        _ = await restoreJourneySnapshot(into: journeyStore, userID: paths.userID)
        _ = await restoreLifelogSnapshot(into: lifelogStore, userID: paths.userID)
        _ = await restoreSettingsSnapshot()
        _ = await restorePhotos(localUserID: paths.userID, forceFull: false)
    }

    private func uploadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        do {
            _ = try await uploadJourneySnapshot(journeyStore: journeyStore, forceFull: true, localUserID: paths.userID)
            _ = try await uploadLifelogSnapshot(lifelogStore: lifelogStore, forceFull: true)
            _ = try await uploadSettingsSnapshot()
        } catch {
            print("☁️ uploadAll failed:", error)
        }
    }

    // MARK: - Upload Internals

    private func uploadJourneySnapshot(
        journeyStore: JourneyStore,
        forceFull: Bool,
        localUserID: String? = nil
    ) async throws -> Bool {
        // Journey incremental sync is handled per-entity via syncJourneyUpsert hooks.
        // Full snapshot upload is only for manual catch-up or initial sync.
        guard forceFull else { return false }
        let journeys = await MainActor.run { journeyStore.journeys }
        guard !journeys.isEmpty else { return false }
        try await journeySync.ensureZone()

        // Pre-fetch already-uploaded photo filenames to skip redundant uploads.
        var alreadyUploaded: Set<String>?
        if localUserID != nil {
            alreadyUploaded = try? await photoSync.fetchUploadedFilenames()
        }

        for route in journeys {
            try await journeySync.uploadJourney(route)
            if let userID = localUserID {
                try await uploadPhotosForJourney(route, localUserID: userID, alreadyUploaded: alreadyUploaded)
            }
        }
        return true
    }

    private func uploadLifelogSnapshot(
        lifelogStore: LifelogStore,
        forceFull: Bool
    ) async throws -> Bool {
        try await lifelogSync.ensureZone()
        try await lifelogMoodSync.ensureZone()
        let (dayBatches, moodByDay, deletedMoodDayKeys) = await MainActor.run {
            if forceFull {
                return (
                    lifelogStore.snapshotPointsByDay(),
                    lifelogStore.snapshotMoodByDay(),
                    lifelogStore.snapshotDeletedMoodDayKeys()
                )
            }
            return (
                lifelogStore.snapshotDirtyPointsByDay(),
                lifelogStore.snapshotDirtyMoodByDay(),
                lifelogStore.snapshotDeletedMoodDayKeys()
            )
        }
        guard !dayBatches.isEmpty || !moodByDay.isEmpty || !deletedMoodDayKeys.isEmpty else {
            return false
        }
        try await lifelogSync.uploadBatches(dayBatches)
        try await lifelogMoodSync.uploadMoods(moodByDay)
        for dayKey in deletedMoodDayKeys {
            try await lifelogMoodSync.deleteMood(dayKey: dayKey)
        }
        await MainActor.run {
            lifelogStore.clearDirtyCloudSyncState(
                uploadedPointDayKeys: Array(dayBatches.keys),
                uploadedMoodDayKeys: Array(moodByDay.keys),
                deletedMoodDayKeys: deletedMoodDayKeys
            )
        }
        return true
    }

    private func uploadSettingsSnapshot() async throws -> Bool {
        try await settingsSync.ensureZone()
        let syncable = SettingsCloudKitSync.syncableKeys
        let snapshot = syncable.reduce(into: [String: Any]()) { partial, key in
            if let value = defaults.object(forKey: key) {
                partial[key] = value
            }
        }
        guard !snapshot.isEmpty else { return false }
        try await settingsSync.uploadSettings(snapshot)
        return true
    }

    // MARK: - Photo Sync

    private func uploadPhotosForJourney(
        _ journey: JourneyRoute,
        localUserID: String,
        alreadyUploaded: Set<String>? = nil
    ) async throws {
        let photosDir = StoragePath(userID: localUserID).photosDir
        let filenames = Self.allPhotoFilenames(from: journey)
        guard !filenames.isEmpty else { return }
        try await photoSync.ensureZone()
        for filename in filenames {
            if let existing = alreadyUploaded, existing.contains(filename) { continue }
            let url = photosDir.appendingPathComponent(filename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try await photoSync.uploadPhoto(
                filename: filename,
                imageURL: url,
                journeyID: journey.id
            )
        }
    }

    private func restorePhotos(localUserID: String, forceFull: Bool) async -> Int {
        do {
            try await photoSync.ensureZone()
            let markerKey = Self.lastPhotoSyncAtKey(for: localUserID)
            let modifiedAfter = forceFull ? nil : (defaults.object(forKey: markerKey) as? Date)
            let photosDir = StoragePath(userID: localUserID).photosDir
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            var wrote = 0
            var newestDate: Date?
            try await photoSync.enumerateSnapshots(modifiedAfter: modifiedAfter) { snapshot in
                if let d = newestDate {
                    if snapshot.modifiedAt > d { newestDate = snapshot.modifiedAt }
                } else {
                    newestDate = snapshot.modifiedAt
                }
                guard !snapshot.isDeleted, let data = snapshot.data else { return }
                let dest = photosDir.appendingPathComponent(snapshot.photoID, isDirectory: false)
                if !forceFull && FileManager.default.fileExists(atPath: dest.path) { return }
                try data.write(to: dest, options: .atomic)
                wrote += 1
            }
            if let newest = newestDate {
                defaults.set(newest, forKey: markerKey)
            }
            return wrote
        } catch {
            print("☁️ restore photos failed:", error)
            return -1
        }
    }

    nonisolated private static func allPhotoFilenames(from journey: JourneyRoute) -> [String] {
        var names: [String] = []
        for memory in journey.memories {
            for path in memory.imagePaths {
                let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { names.append(cleaned) }
            }
        }
        for path in journey.overallMemoryImagePaths {
            let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { names.append(cleaned) }
        }
        return names
    }

    // MARK: - Status Helpers

    nonisolated static func statusKey(for userID: String) -> String {
        "\(statusKeyPrefix)\(userID)"
    }

    nonisolated static func statusAtKey(for userID: String) -> String {
        "\(statusAtKeyPrefix)\(userID)"
    }

    nonisolated static func statusSnapshot(
        defaults: UserDefaults = .standard,
        localUserID: String,
        accountUserID: String?
    ) -> CloudKitStatusSnapshot {
        let preferredIDs = [accountUserID, localUserID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for userID in preferredIDs {
            let status = defaults.string(forKey: statusKey(for: userID))
            let at = defaults.object(forKey: statusAtKey(for: userID)) as? Date
            if status != nil || at != nil {
                return CloudKitStatusSnapshot(status: status, at: at)
            }
        }

        return CloudKitStatusSnapshot(status: nil, at: nil)
    }

    nonisolated private static func lastJourneySyncAtKey(for userID: String) -> String {
        "\(lastJourneySyncAtKeyPrefix)\(userID)"
    }

    nonisolated private static func lastLifelogSyncAtKey(for userID: String) -> String {
        "\(lastLifelogSyncAtKeyPrefix)\(userID)"
    }

    nonisolated private static func lastMoodSyncAtKey(for userID: String) -> String {
        "\(lastMoodSyncAtKeyPrefix)\(userID)"
    }

    nonisolated private static func lastPhotoSyncAtKey(for userID: String) -> String {
        "\(lastPhotoSyncAtKeyPrefix)\(userID)"
    }

    private func writeStatus(userID: String, status: String) {
        defaults.set(status, forKey: Self.statusKey(for: userID))
        defaults.set(Date(), forKey: Self.statusAtKey(for: userID))
    }
}
