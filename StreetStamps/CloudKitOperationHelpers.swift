import CloudKit
import Foundation

// MARK: - Zone Management

/// Caches zone creation results so each zone is only created once per app session.
actor CloudKitZoneCache {
    static let shared = CloudKitZoneCache()
    private var createdZoneIDs: Set<CKRecordZone.ID> = []

    func ensureZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        guard !createdZoneIDs.contains(zoneID) else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await database.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone already exists - treat as success
        }
        createdZoneIDs.insert(zoneID)
    }

    func invalidate(_ zoneID: CKRecordZone.ID) {
        createdZoneIDs.remove(zoneID)
    }
}

// MARK: - Save With Policy

/// Saves a record using CKModifyRecordsOperation with .allKeys save policy,
/// which overwrites server fields on conflict instead of failing.
func cloudKitSaveRecord(_ record: CKRecord, in database: CKDatabase) async throws {
    try await cloudKitSaveRecords([record], in: database)
}

func cloudKitSaveRecords(_ records: [CKRecord], in database: CKDatabase) async throws {
    guard !records.isEmpty else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.isAtomic = false
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
        database.add(operation)
    }
}

/// Hard-deletes records by ID from CloudKit.
func cloudKitDeleteRecords(_ recordIDs: [CKRecord.ID], in database: CKDatabase) async throws {
    guard !recordIDs.isEmpty else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        operation.isAtomic = false
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
        database.add(operation)
    }
}

// MARK: - Paginated Query

/// Fetches all records matching a query, following cursors until exhausted.
func cloudKitQueryAll(
    recordType: String,
    predicate: NSPredicate,
    zoneID: CKRecordZone.ID,
    desiredKeys: [CKRecord.FieldKey]? = nil,
    in database: CKDatabase
) async throws -> [CKRecord] {
    var allRecords: [CKRecord] = []
    let query = CKQuery(recordType: recordType, predicate: predicate)

    // First page
    let (results, cursor) = try await database.records(
        matching: query,
        inZoneWith: zoneID,
        desiredKeys: desiredKeys,
        resultsLimit: CKQueryOperation.maximumResults
    )
    allRecords.append(contentsOf: results.compactMap { try? $0.1.get() })

    // Follow cursors
    var nextCursor = cursor
    while let currentCursor = nextCursor {
        let (moreResults, moreCursor) = try await database.records(
            continuingMatchFrom: currentCursor,
            desiredKeys: desiredKeys,
            resultsLimit: CKQueryOperation.maximumResults
        )
        allRecords.append(contentsOf: moreResults.compactMap { try? $0.1.get() })
        nextCursor = moreCursor
    }

    return allRecords
}
