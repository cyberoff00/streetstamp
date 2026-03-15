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

// MARK: - Sync Coordinator

actor CloudKitSyncService {
    static let shared = CloudKitSyncService()

    private let container: CKContainer
    private let database: CKDatabase
    private let journeySync: JourneyCloudKitSync
    private let lifelogSync: LifelogCloudKitSync
    private let photoSync: PhotoCloudKitSync
    private let settingsSync: SettingsCloudKitSync

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.journeySync = JourneyCloudKitSync(database: database)
        self.lifelogSync = LifelogCloudKitSync(database: database)
        self.photoSync = PhotoCloudKitSync(database: database)
        self.settingsSync = SettingsCloudKitSync(database: database)
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
        try await photoSync.ensureZone()
        try await settingsSync.ensureZone()
    }

    func syncAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async throws {
        guard await isAvailable() else { return }
        try await ensureZones()

        // Download first
        await downloadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)

        // Then upload
        await uploadAll(journeyStore: journeyStore, lifelogStore: lifelogStore, paths: paths)
    }

    private func downloadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        // Download journeys, lifelog, photos, settings
        // Merge with local data
    }

    private func uploadAll(journeyStore: JourneyStore, lifelogStore: LifelogStore, paths: StoragePath) async {
        // Upload changed data
    }
}
