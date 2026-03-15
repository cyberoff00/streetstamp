import CloudKit
import Foundation

enum ICloudSyncDefaultsSnapshot {
    private static let includedPrefix = "streetstamps."
    private static let excludedKeys: Set<String> = [
        "streetstamps.session.v1",
        "streetstamps.firebase_account_state.v1",
        "streetstamps.pending_guest_migration.v1",
        "streetstamps.guest_account_bindings.v1",
        "streetstamps.legacy_guest_bindings.v1",
        "streetstamps.auto_recovered_guest_sources.v1",
        "streetstamps.active_local_profile_id.v1",
        "streetstamps.guest_id.v1"
    ]

    static func filteredValues(from source: [String: Any]) -> [String: Any] {
        source.reduce(into: [String: Any]()) { partial, pair in
            guard pair.key.hasPrefix(includedPrefix) else { return }
            guard !excludedKeys.contains(pair.key) else { return }
            guard PropertyListSerialization.propertyList(pair.value, isValidFor: .binary) else { return }
            partial[pair.key] = pair.value
        }
    }

    static func capture(defaults: UserDefaults = .standard) -> [String: Any] {
        filteredValues(from: defaults.dictionaryRepresentation())
    }

    static func apply(_ values: [String: Any], defaults: UserDefaults = .standard) {
        values.forEach { key, value in
            defaults.set(value, forKey: key)
        }
    }
}

actor ICloudSyncService {
    static let shared = ICloudSyncService()

    private let container: CKContainer
    private let database: CKDatabase
    private let defaults: UserDefaults
    private let fileManager: FileManager

    private let recordType = "StreetStampsUserBackup"
    private let defaultsField = "defaultsPlist"
    private let payloadField = "payloadAsset"
    private let exportedAtField = "exportedAt"
    private let schemaField = "schemaVersion"
    private let schemaVersion: Int64 = 1
    private let appVersionField = "appVersion"
    private let userIDField = "userID"
    private static let statusKeyPrefix = "streetstamps.icloud.sync.status."
    private static let statusAtKeyPrefix = "streetstamps.icloud.sync.status_at."
    private static let lastRestoreKeyPrefix = "streetstamps.icloud.sync.last_restore."
    private static let lastUploadKeyPrefix = "streetstamps.icloud.sync.last_upload."

    init(
        container: CKContainer = .default(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func isAccountAvailable() async -> Bool {
        do {
            let status = try await accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    func restoreLatestIfNeeded(userID: String, paths: StoragePath, force: Bool = false) async -> Bool {
        guard force || AppSettings.isICloudSyncEnabled else { return false }
        guard await isAccountAvailable() else { return false }

        do {
            var record = try await fetchRecord()
            if record == nil {
                record = try await fetchLegacyRecord(userID: userID)
            }
            guard let record else {
                if force {
                    writeStatus(userID: userID, status: "no_backup")
                }
                return false
            }
            guard let remoteDate = record.modificationDate else { return false }

            let markerKey = Self.lastRestoreMarkerKey(for: userID)
            if let lastRestoreDate = defaults.object(forKey: markerKey) as? Date,
               remoteDate <= lastRestoreDate {
                if force {
                    writeStatus(userID: userID, status: "already_latest")
                }
                return false
            }

            try restore(record: record, to: paths)
            defaults.set(remoteDate, forKey: markerKey)
            writeStatus(userID: userID, status: "restore_success")
            return true
        } catch {
            print("☁️ iCloud restore failed:", error)
            writeStatus(userID: userID, status: "restore_failed")
            return false
        }
    }

    func uploadSnapshotIfEnabled(userID: String, paths: StoragePath, reason: String) async {
        guard AppSettings.isICloudSyncEnabled else { return }
        guard await isAccountAvailable() else { return }

        do {
            try paths.ensureBaseDirectoriesExist()
            let payloadURL = try makePayloadArchiveURL(from: paths.userRoot)
            defer { try? fileManager.removeItem(at: payloadURL) }

            let defaultsDict = ICloudSyncDefaultsSnapshot.capture(defaults: defaults) as NSDictionary
            let defaultsData = try PropertyListSerialization.data(
                fromPropertyList: defaultsDict,
                format: .binary,
                options: 0
            )

            let record: CKRecord
            if let existing = try await fetchRecord() {
                record = existing
            } else {
                record = CKRecord(
                    recordType: recordType,
                    recordID: try await getRecordID()
                )
            }
            record[userIDField] = userID as CKRecordValue
            record[appVersionField] = appVersion() as CKRecordValue
            record[exportedAtField] = Date() as CKRecordValue
            record[schemaField] = schemaVersion as CKRecordValue
            record[defaultsField] = defaultsData as CKRecordValue
            record[payloadField] = CKAsset(fileURL: payloadURL)

            _ = try await saveRecord(record)
            defaults.set(Date(), forKey: Self.lastUploadMarkerKey(for: userID))
            writeStatus(userID: userID, status: "upload_success")
            print("☁️ iCloud snapshot uploaded (\(reason))")
        } catch {
            print("☁️ iCloud upload failed:", error)
            writeStatus(userID: userID, status: "upload_failed")
        }
    }

    private func restore(record: CKRecord, to paths: StoragePath) throws {
        guard let asset = record[payloadField] as? CKAsset,
              let payloadURL = asset.fileURL else {
            throw NSError(domain: "ICloudSyncService", code: 1)
        }

        let payload = try Data(contentsOf: payloadURL)
        guard let wrapper = try NSKeyedUnarchiver.unarchivedObject(ofClass: FileWrapper.self, from: payload) else {
            throw NSError(domain: "ICloudSyncService", code: 2)
        }

        let stagingDir = fileManager.temporaryDirectory
            .appendingPathComponent("ss-icloud-restore-\(UUID().uuidString)", isDirectory: true)
        let stagedRoot = stagingDir.appendingPathComponent("userRoot", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDir) }

        try wrapper.write(to: stagedRoot, options: .atomic, originalContentsURL: nil)

        let parent = paths.userRoot.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: paths.userRoot.path) {
            try fileManager.removeItem(at: paths.userRoot)
        }
        try fileManager.moveItem(at: stagedRoot, to: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        if let defaultsData = record[defaultsField] as? Data,
           let plist = try PropertyListSerialization.propertyList(
               from: defaultsData,
               options: [],
               format: nil
           ) as? [String: Any] {
            ICloudSyncDefaultsSnapshot.apply(plist, defaults: defaults)
        }
    }

    private func makePayloadArchiveURL(from userRoot: URL) throws -> URL {
        let wrapper = try FileWrapper(url: userRoot, options: .immediate)
        let data = try NSKeyedArchiver.archivedData(withRootObject: wrapper, requiringSecureCoding: true)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("ss-icloud-backup-\(UUID().uuidString).bin", isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func getRecordID() async throws -> CKRecord.ID {
        let userRecordID = try await container.userRecordID()
        return CKRecord.ID(recordName: "backup_\(userRecordID.recordName)")
    }

    nonisolated static func lastRestoreMarkerKey(for userID: String) -> String {
        "\(lastRestoreKeyPrefix)\(userID)"
    }

    nonisolated static func lastUploadMarkerKey(for userID: String) -> String {
        "\(lastUploadKeyPrefix)\(userID)"
    }

    nonisolated static func statusKey(for userID: String) -> String {
        "\(statusKeyPrefix)\(userID)"
    }

    nonisolated static func statusAtKey(for userID: String) -> String {
        "\(statusAtKeyPrefix)\(userID)"
    }

    private func writeStatus(userID: String, status: String) {
        defaults.set(status, forKey: Self.statusKey(for: userID))
        defaults.set(Date(), forKey: Self.statusAtKey(for: userID))
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func fetchRecord() async throws -> CKRecord? {
        do {
            let recordID = try await getRecordID()
            return try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: recordID) { record, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: record)
                    }
                }
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    private func fetchLegacyRecord(userID: String) async throws -> CKRecord? {
        do {
            let legacyID = CKRecord.ID(recordName: "backup_\(userID.replacingOccurrences(of: "/", with: "_"))")
            return try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: legacyID) { record, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: record)
                    }
                }
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let saved else {
                    continuation.resume(throwing: NSError(domain: "ICloudSyncService", code: 3))
                    return
                }
                continuation.resume(returning: saved)
            }
        }
    }
}
