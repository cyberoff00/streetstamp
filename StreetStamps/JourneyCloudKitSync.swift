import CloudKit
import Foundation

struct JourneyCloudSnapshot {
    var journeyID: String
    var journey: JourneyRoute?
    var modifiedAt: Date
    var isDeleted: Bool
}

actor JourneyCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "JourneysZone", ownerName: CKCurrentUserDefaultName)
    private let journeyIDField = "journeyID"
    private let dataField = "data"
    private let modifiedAtField = "modifiedAt"
    private let isDeletedField = "isDeleted"

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        try await CloudKitZoneCache.shared.ensureZone(zoneID, in: database)
    }

    func uploadJourney(_ journey: JourneyRoute) async throws {
        let recordID = CKRecord.ID(recordName: "journey_\(journey.id)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.journey, recordID: recordID)

        let encoder = JSONEncoder()
        record[journeyIDField] = journey.id as CKRecordValue
        record[dataField] = try encoder.encode(journey) as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 0 as CKRecordValue

        try await cloudKitSaveRecord(record, in: database)
    }

    func downloadJourneys(modifiedAfter: Date?) async throws -> [JourneyRoute] {
        try await downloadSnapshots(modifiedAfter: modifiedAfter)
            .compactMap { snapshot in
                guard !snapshot.isDeleted else { return nil }
                return snapshot.journey
            }
    }

    func downloadSnapshots(modifiedAfter: Date?) async throws -> [JourneyCloudSnapshot] {
        let predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "\(modifiedAtField) > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let records = try await cloudKitQueryAll(
            recordType: CloudKitRecordType.journey,
            predicate: predicate,
            zoneID: zoneID,
            in: database
        )

        var snapshots: [JourneyCloudSnapshot] = []
        for record in records {
            guard let journeyID = record[journeyIDField] as? String else { continue }
            let modifiedAt = (record[modifiedAtField] as? Date) ?? record.modificationDate ?? .distantPast
            let isDeleted = ((record[isDeletedField] as? Int64) ?? 0) != 0
            let journey: JourneyRoute?
            if let data = record[dataField] as? Data {
                journey = try JSONDecoder().decode(JourneyRoute.self, from: data)
            } else {
                journey = nil
            }
            snapshots.append(
                JourneyCloudSnapshot(
                    journeyID: journeyID,
                    journey: journey,
                    modifiedAt: modifiedAt,
                    isDeleted: isDeleted
                )
            )
        }
        return snapshots
    }

    func deleteJourney(id: String) async throws {
        let recordID = CKRecord.ID(recordName: "journey_\(id)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.journey, recordID: recordID)
        record[journeyIDField] = id as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 1 as CKRecordValue
        record[dataField] = nil
        try await cloudKitSaveRecord(record, in: database)
    }
}
