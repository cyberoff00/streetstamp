import CloudKit
import Foundation

actor SettingsCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "SettingsZone", ownerName: CKCurrentUserDefaultName)

    /// Only these keys are safe to sync cross-device.
    /// Auth tokens, session state, sync timestamps, debug flags, and draft state are excluded.
    static let syncableKeys: Set<String> = [
        AppSettings.voiceBroadcastEnabledKey,
        AppSettings.voiceBroadcastIntervalKMKey,
        AppSettings.longStationaryReminderEnabledKey,
        AppSettings.liveActivityEnabledKey,
        AppSettings.dailyTrackingPrecisionKey,
        AppSettings.lifelogPassiveEnabledKey,
        "streetstamps.map.appearance",
        "streetstamps.profile.visibility",
        "app_language",
        UserScopedProfileStateStore.globalEconomyKey,
        UserScopedProfileStateStore.globalAvatarLoadoutKey,
    ]

    static let mergeOnRestoreKeys: Set<String> = [
        UserScopedProfileStateStore.globalEconomyKey,
    ]

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        try await CloudKitZoneCache.shared.ensureZone(zoneID, in: database)
    }

    func uploadSettings(_ allSettings: [String: Any], accountID: String) async throws {
        let filtered = allSettings.filter { Self.syncableKeys.contains($0.key) }
        guard !filtered.isEmpty else { return }

        let recordID = CKRecord.ID(recordName: "settings_\(accountID)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.settings, recordID: recordID)

        let data = try PropertyListSerialization.data(
            fromPropertyList: filtered as NSDictionary,
            format: .binary,
            options: 0
        )
        record["data"] = data as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue

        try await cloudKitSaveRecord(record, in: database)
    }

    func downloadSettings(accountID: String) async throws -> [String: Any]? {
        let recordID = CKRecord.ID(recordName: "settings_\(accountID)", zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            if let data = record["data"] as? Data,
               let plist = try PropertyListSerialization.propertyList(
                   from: data, options: [], format: nil
               ) as? [String: Any] {
                // Double-filter on restore to guard against schema drift
                return plist.filter { Self.syncableKeys.contains($0.key) }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        return nil
    }
}
