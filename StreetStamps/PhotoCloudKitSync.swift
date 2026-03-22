import CloudKit
import Foundation
import UIKit

struct PhotoCloudSnapshot {
    var photoID: String
    var memoryID: String?
    var journeyID: String?
    var sortOrder: Int
    var modifiedAt: Date
    var isDeleted: Bool
    var data: Data?
}

actor PhotoCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "PhotosZone", ownerName: CKCurrentUserDefaultName)
    private let maxPhotoSizeKB = 500

    private let photoIDField = "photoID"
    private let memoryIDField = "memoryID"
    private let journeyIDField = "journeyID"
    private let sortOrderField = "sortOrder"
    private let modifiedAtField = "modifiedAt"
    private let isDeletedField = "isDeleted"
    private let filenameField = "filename"

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        try await CloudKitZoneCache.shared.ensureZone(zoneID, in: database)
    }

    func uploadPhoto(
        filename: String,
        imageURL: URL,
        memoryID: String? = nil,
        journeyID: String? = nil,
        sortOrder: Int = 0
    ) async throws {
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return }
        let compressed = try compressImage(image, maxSizeKB: maxPhotoSizeKB)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try compressed.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordID = CKRecord.ID(recordName: "photo_\(filename)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.photo, recordID: recordID)

        record[photoIDField] = filename as CKRecordValue
        record[filenameField] = filename as CKRecordValue
        record["asset"] = CKAsset(fileURL: tempURL)
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 0 as CKRecordValue
        if let memoryID {
            record[memoryIDField] = memoryID as CKRecordValue
        }
        if let journeyID {
            record[journeyIDField] = journeyID as CKRecordValue
        }
        record[sortOrderField] = sortOrder as CKRecordValue

        try await cloudKitSaveRecord(record, in: database)
    }

    func downloadPhotos(modifiedAfter: Date?) async throws -> [(filename: String, data: Data)] {
        var result: [(String, Data)] = []
        try await enumerateSnapshots(modifiedAfter: modifiedAfter) { snapshot in
            guard !snapshot.isDeleted, let data = snapshot.data else { return }
            result.append((snapshot.photoID, data))
        }
        return result
    }

    func downloadSnapshots(modifiedAfter: Date?) async throws -> [PhotoCloudSnapshot] {
        var snapshots: [PhotoCloudSnapshot] = []
        try await enumerateSnapshots(modifiedAfter: modifiedAfter) { snapshot in
            snapshots.append(snapshot)
        }
        return snapshots
    }

    /// Streams photo records one page at a time, calling `handler` per snapshot
    /// so the caller can write to disk and release memory before the next page.
    func enumerateSnapshots(
        modifiedAfter: Date?,
        handler: (PhotoCloudSnapshot) throws -> Void
    ) async throws {
        let predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "\(modifiedAtField) > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: CloudKitRecordType.photo, predicate: predicate)
        var (results, cursor) = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            resultsLimit: CKQueryOperation.maximumResults
        )

        try processRecordPage(results, handler: handler)

        while let currentCursor = cursor {
            let (moreResults, moreCursor) = try await database.records(
                continuingMatchFrom: currentCursor,
                resultsLimit: CKQueryOperation.maximumResults
            )
            try processRecordPage(moreResults, handler: handler)
            cursor = moreCursor
        }
    }

    private func processRecordPage(
        _ results: [(CKRecord.ID, Result<CKRecord, Error>)],
        handler: (PhotoCloudSnapshot) throws -> Void
    ) throws {
        for (_, result) in results {
            guard let record = try? result.get() else { continue }
            let photoID = (record[photoIDField] as? String)
                ?? (record[filenameField] as? String)
                ?? record.recordID.recordName
            let modifiedAt = (record[modifiedAtField] as? Date) ?? record.modificationDate ?? .distantPast
            let isDeleted = ((record[isDeletedField] as? Int64) ?? 0) != 0

            var photoData: Data?
            if let asset = record["asset"] as? CKAsset, let fileURL = asset.fileURL {
                photoData = try? Data(contentsOf: fileURL)
            }

            try handler(
                PhotoCloudSnapshot(
                    photoID: photoID,
                    memoryID: record[memoryIDField] as? String,
                    journeyID: record[journeyIDField] as? String,
                    sortOrder: (record[sortOrderField] as? Int) ?? 0,
                    modifiedAt: modifiedAt,
                    isDeleted: isDeleted,
                    data: photoData
                )
            )
        }
    }

    /// Returns the set of filenames already uploaded to CloudKit (lightweight metadata-only query).
    func fetchUploadedFilenames() async throws -> Set<String> {
        let predicate = NSPredicate(format: "\(isDeletedField) == 0")
        let query = CKQuery(recordType: CloudKitRecordType.photo, predicate: predicate)
        var names = Set<String>()

        var (results, cursor) = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: [photoIDField, filenameField],
            resultsLimit: CKQueryOperation.maximumResults
        )
        for (_, result) in results {
            guard let record = try? result.get() else { continue }
            let name = (record[photoIDField] as? String)
                ?? (record[filenameField] as? String)
                ?? record.recordID.recordName
            names.insert(name)
        }
        while let currentCursor = cursor {
            let (moreResults, moreCursor) = try await database.records(
                continuingMatchFrom: currentCursor,
                desiredKeys: [photoIDField, filenameField],
                resultsLimit: CKQueryOperation.maximumResults
            )
            for (_, result) in moreResults {
                guard let record = try? result.get() else { continue }
                let name = (record[photoIDField] as? String)
                    ?? (record[filenameField] as? String)
                    ?? record.recordID.recordName
                names.insert(name)
            }
            cursor = moreCursor
        }
        return names
    }

    func deletePhoto(filename: String) async throws {
        let recordID = CKRecord.ID(recordName: "photo_\(filename)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.photo, recordID: recordID)
        record[photoIDField] = filename as CKRecordValue
        record[filenameField] = filename as CKRecordValue
        record[modifiedAtField] = Date() as CKRecordValue
        record[isDeletedField] = 1 as CKRecordValue
        try await cloudKitSaveRecord(record, in: database)
    }

    private func compressImage(_ image: UIImage, maxSizeKB: Int) throws -> Data {
        var quality: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: quality)!

        while data.count > maxSizeKB * 1024 && quality > 0.1 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)!
        }

        return data
    }
}
