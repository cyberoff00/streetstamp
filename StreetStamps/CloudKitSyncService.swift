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

    var totalCount: Int {
        restoredJourneyCount + restoredLifelogCount
    }
}

// MARK: - Sync Coordinator

actor CloudKitSyncService {
    static let shared = CloudKitSyncService()
    private static let lastJourneySyncAtKeyPrefix = "streetstamps.cloudkit.journey.last_sync."
    private static let lastLifelogSyncAtKeyPrefix = "streetstamps.cloudkit.lifelog.last_sync."
    private static let lastMoodSyncAtKeyPrefix = "streetstamps.cloudkit.lifelog_mood.last_sync."
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

    func syncJourneyUpsert(_ journey: JourneyRoute) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAvailable() else { return }
        do {
            try await journeySync.ensureZone()
            try await journeySync.uploadJourney(journey)
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

    func syncCurrentState(
        userID: String,
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
                forceFull: forceFullJourneyUpload
            )
            let didUploadLifelog = try await uploadLifelogSnapshot(
                lifelogStore: lifelogStore,
                forceFull: forceFullLifelogUpload
            )
            guard didUploadJourneys || didUploadLifelog || forceFullJourneyUpload || forceFullLifelogUpload else {
                return
            }
            writeStatus(userID: userID, status: "upload_success")
            print("☁️ incremental iCloud sync uploaded (\(reason))")
        } catch {
            print("☁️ incremental iCloud sync failed:", error)
            writeStatus(userID: userID, status: "upload_failed")
        }
    }

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
            return 0
        }
    }

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
            return 0
        }
    }

    func restoreAllData(
        into journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        cityCache: CityCache? = nil,
        userID: String,
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

        let restoredJourneyCount = await restoreJourneySnapshot(
            into: journeyStore,
            userID: userID,
            forceFull: forceFull
        )
        let restoredLifelogCount = await restoreLifelogSnapshot(
            into: lifelogStore,
            userID: userID,
            forceFull: forceFull
        )
        let result = CloudKitRestoreResult(
            restoredJourneyCount: restoredJourneyCount,
            restoredLifelogCount: restoredLifelogCount
        )

        await MainActor.run {
            Self.rebuildDerivedCityStateIfNeeded(
                restoredJourneyCount: restoredJourneyCount,
                cityCache: cityCache
            )
        }

        if writeManualStatus {
            if result.totalCount > 0 {
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

    func syncAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async throws {
        guard await isAvailable() else { return }
        try await ensureZones()

        await downloadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)
        await uploadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)
    }

    private func uploadJourneySnapshot(
        journeyStore: JourneyStore,
        forceFull: Bool
    ) async throws -> Bool {
        guard forceFull else { return false }
        let journeys = await MainActor.run { journeyStore.journeys }
        guard !journeys.isEmpty else { return false }
        try await journeySync.ensureZone()
        for route in journeys {
            try await journeySync.uploadJourney(route)
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

    private func downloadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        // Download journeys, lifelog, photos, settings
        // Merge with local data
    }

    private func uploadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        // Upload changed data
    }

    nonisolated static func statusKey(for userID: String) -> String {
        "\(statusKeyPrefix)\(userID)"
    }

    nonisolated static func statusAtKey(for userID: String) -> String {
        "\(statusAtKeyPrefix)\(userID)"
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

    private func writeStatus(userID: String, status: String) {
        defaults.set(status, forKey: Self.statusKey(for: userID))
        defaults.set(Date(), forKey: Self.statusAtKey(for: userID))
    }
}
