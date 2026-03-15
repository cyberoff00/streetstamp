import CloudKit
import Foundation

actor SettingsCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "SettingsZone", ownerName: CKCurrentUserDefaultName)

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)
    }

    func uploadSettings(_ settings: [String: Any]) async throws {
        let recordID = CKRecord.ID(recordName: "settings", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.settings, recordID: recordID)

        let data = try PropertyListSerialization.data(fromPropertyList: settings as NSDictionary, format: .binary, options: 0)
        record["data"] = data as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue

        _ = try await database.save(record)
    }

    func downloadSettings() async throws -> [String: Any]? {
        let recordID = CKRecord.ID(recordName: "settings", zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            if let data = record["data"] as? Data,
               let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        return nil
    }

    func uploadCityCache(_ cities: [String: Any]) async throws {
        let recordID = CKRecord.ID(recordName: "cityCache", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.cityCache, recordID: recordID)

        let data = try JSONSerialization.data(withJSONObject: cities)
        record["data"] = data as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue

        _ = try await database.save(record)
    }

    func downloadCityCache() async throws -> [String: Any]? {
        let recordID = CKRecord.ID(recordName: "cityCache", zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            if let data = record["data"] as? Data,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        return nil
    }
}
