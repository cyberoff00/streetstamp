import CloudKit
import Foundation

struct LifelogMoodCloudSnapshot {
    var dayKey: String
    var mood: String?
    var modifiedAt: Date
    var isDeleted: Bool
}

actor LifelogMoodCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "LifelogMoodZone", ownerName: CKCurrentUserDefaultName)
    private let dayKeyField = "dayKey"
    private let moodField = "mood"
    private let modifiedAtField = "modifiedAt"
    private let isDeletedField = "isDeleted"

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        try await CloudKitZoneCache.shared.ensureZone(zoneID, in: database)
    }

    func uploadMood(dayKey: String, mood: String) async throws {
        let recordID = CKRecord.ID(recordName: "lifelog_mood_\(dayKey)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.lifelogMood, recordID: recordID)
        record[dayKeyField] = dayKey as CKRecordValue
        record[moodField] = mood as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 0 as CKRecordValue
        try await cloudKitSaveRecord(record, in: database)
    }

    func uploadMoods(_ moods: [String: String]) async throws {
        for (dayKey, mood) in moods {
            try await uploadMood(dayKey: dayKey, mood: mood)
        }
    }

    func downloadSnapshots(modifiedAfter: Date? = nil) async throws -> [LifelogMoodCloudSnapshot] {
        let predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "\(modifiedAtField) > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let records = try await cloudKitQueryAll(
            recordType: CloudKitRecordType.lifelogMood,
            predicate: predicate,
            zoneID: zoneID,
            in: database
        )

        var snapshots: [LifelogMoodCloudSnapshot] = []
        for record in records {
            guard let dayKey = record[dayKeyField] as? String else { continue }
            snapshots.append(
                LifelogMoodCloudSnapshot(
                    dayKey: dayKey,
                    mood: record[moodField] as? String,
                    modifiedAt: (record[modifiedAtField] as? Date) ?? record.modificationDate ?? .distantPast,
                    isDeleted: ((record[isDeletedField] as? Int64) ?? 0) != 0
                )
            )
        }
        return snapshots
    }

    func deleteMood(dayKey: String) async throws {
        let recordID = CKRecord.ID(recordName: "lifelog_mood_\(dayKey)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.lifelogMood, recordID: recordID)
        record[dayKeyField] = dayKey as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 1 as CKRecordValue
        record[moodField] = nil
        try await cloudKitSaveRecord(record, in: database)
    }
}
