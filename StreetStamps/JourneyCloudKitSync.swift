import CloudKit
import Foundation

actor JourneyCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "JourneysZone", ownerName: CKCurrentUserDefaultName)

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)
    }

    func uploadJourney(_ journey: JourneyRoute) async throws {
        let recordID = CKRecord.ID(recordName: "journey_\(journey.id)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.journey, recordID: recordID)

        let encoder = JSONEncoder()
        record["journeyID"] = journey.id as CKRecordValue
        record["data"] = try encoder.encode(journey) as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue

        _ = try await database.save(record)
    }

    func downloadJourneys(modifiedAfter: Date?) async throws -> [JourneyRoute] {
        var predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "modifiedAt > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: CloudKitRecordType.journey, predicate: predicate)
        let records = try await database.records(matching: query, inZoneWith: zoneID)

        var journeys: [JourneyRoute] = []
        for record in records {
            if let data = record["data"] as? Data {
                let journey = try JSONDecoder().decode(JourneyRoute.self, from: data)
                journeys.append(journey)
            }
        }
        return journeys
    }

    func deleteJourney(id: String) async throws {
        let recordID = CKRecord.ID(recordName: "journey_\(id)", zoneID: zoneID)
        _ = try await database.deleteRecord(withID: recordID)
    }
}
