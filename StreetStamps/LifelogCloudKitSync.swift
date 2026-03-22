import CloudKit
import Foundation

struct LifelogDayCloudSnapshot {
    var dayKey: String
    var points: [LifelogStore.LifelogTrackPoint]
    var modifiedAt: Date
    var isDeleted: Bool
}

actor LifelogCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "LifelogZone", ownerName: CKCurrentUserDefaultName)
    private let dayKeyField = "dayKey"
    private let pointsField = "points"
    private let modifiedAtField = "modifiedAt"
    private let isDeletedField = "isDeleted"

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        try await CloudKitZoneCache.shared.ensureZone(zoneID, in: database)
    }

    func uploadBatch(dayKey: String, points: [LifelogStore.LifelogTrackPoint]) async throws {
        let recordID = CKRecord.ID(recordName: "lifelog_\(dayKey)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.passiveLifelogBatch, recordID: recordID)

        let encoder = JSONEncoder()
        let compressed = try encoder.encode(points)

        record[dayKeyField] = dayKey as CKRecordValue
        record[pointsField] = compressed as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 0 as CKRecordValue

        try await cloudKitSaveRecord(record, in: database)
    }

    func uploadBatches(_ batches: [String: [LifelogStore.LifelogTrackPoint]]) async throws {
        for (dayKey, points) in batches {
            try await uploadBatch(dayKey: dayKey, points: points)
        }
    }

    func downloadBatches(modifiedAfter: Date?) async throws -> [String: [LifelogStore.LifelogTrackPoint]] {
        let snapshots = try await downloadSnapshots(modifiedAfter: modifiedAfter)
        return snapshots.reduce(into: [String: [LifelogStore.LifelogTrackPoint]]()) { partial, snapshot in
            guard !snapshot.isDeleted else { return }
            partial[snapshot.dayKey] = snapshot.points
        }
    }

    func downloadSnapshots(modifiedAfter: Date?) async throws -> [LifelogDayCloudSnapshot] {
        let predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "\(modifiedAtField) > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let records = try await cloudKitQueryAll(
            recordType: CloudKitRecordType.passiveLifelogBatch,
            predicate: predicate,
            zoneID: zoneID,
            in: database
        )

        var snapshots: [LifelogDayCloudSnapshot] = []
        for record in records {
            guard let dayKey = record[dayKeyField] as? String else { continue }
            let modifiedAt = (record[modifiedAtField] as? Date) ?? record.modificationDate ?? .distantPast
            let isDeleted = ((record[isDeletedField] as? Int64) ?? 0) != 0
            let points: [LifelogStore.LifelogTrackPoint]
            if let data = record[pointsField] as? Data {
                points = try JSONDecoder().decode([LifelogStore.LifelogTrackPoint].self, from: data)
            } else {
                points = []
            }
            snapshots.append(
                LifelogDayCloudSnapshot(
                    dayKey: dayKey,
                    points: points,
                    modifiedAt: modifiedAt,
                    isDeleted: isDeleted
                )
            )
        }
        return snapshots
    }

    func deleteBatch(dayKey: String) async throws {
        let recordID = CKRecord.ID(recordName: "lifelog_\(dayKey)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.passiveLifelogBatch, recordID: recordID)
        record[dayKeyField] = dayKey as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 1 as CKRecordValue
        record[pointsField] = nil
        try await cloudKitSaveRecord(record, in: database)
    }
}
