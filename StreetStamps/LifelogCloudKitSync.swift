import CloudKit
import Foundation

actor LifelogCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "LifelogZone", ownerName: CKCurrentUserDefaultName)
    private let batchSize = 1000

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)
    }

    func uploadBatch(yearMonth: String, points: [LifelogStore.LifelogTrackPoint]) async throws {
        let recordID = CKRecord.ID(recordName: "lifelog_\(yearMonth)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.lifelogBatch, recordID: recordID)

        let encoder = JSONEncoder()
        let compressed = try encoder.encode(points)

        record["yearMonth"] = yearMonth as CKRecordValue
        record["points"] = compressed as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue

        _ = try await database.save(record)
    }

    func downloadBatches(modifiedAfter: Date?) async throws -> [String: [LifelogStore.LifelogTrackPoint]] {
        var predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "modifiedAt > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: CloudKitRecordType.lifelogBatch, predicate: predicate)
        let records = try await database.records(matching: query, inZoneWith: zoneID)

        var batches: [String: [LifelogStore.LifelogTrackPoint]] = [:]
        for record in records {
            if let yearMonth = record["yearMonth"] as? String,
               let data = record["points"] as? Data {
                let points = try JSONDecoder().decode([LifelogStore.LifelogTrackPoint].self, from: data)
                batches[yearMonth] = points
            }
        }
        return batches
    }
}
