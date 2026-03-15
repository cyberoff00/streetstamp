import CloudKit
import Foundation
import UIKit

actor PhotoCloudKitSync {
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "PhotosZone", ownerName: CKCurrentUserDefaultName)
    private let maxPhotoSizeKB = 500

    init(database: CKDatabase) {
        self.database = database
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)
    }

    func uploadPhoto(filename: String, imageURL: URL) async throws {
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return }
        let compressed = try compressImage(image, maxSizeKB: maxPhotoSizeKB)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try compressed.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordID = CKRecord.ID(recordName: "photo_\(filename)", zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.photo, recordID: recordID)

        record["filename"] = filename as CKRecordValue
        record["asset"] = CKAsset(fileURL: tempURL)
        record["modifiedAt"] = Date() as CKRecordValue

        _ = try await database.save(record)
    }

    func downloadPhotos(modifiedAfter: Date?) async throws -> [(filename: String, data: Data)] {
        var predicate: NSPredicate
        if let date = modifiedAfter {
            predicate = NSPredicate(format: "modifiedAt > %@", date as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: CloudKitRecordType.photo, predicate: predicate)
        let records = try await database.records(matching: query, inZoneWith: zoneID)

        var photos: [(String, Data)] = []
        for record in records {
            if let filename = record["filename"] as? String,
               let asset = record["asset"] as? CKAsset,
               let fileURL = asset.fileURL,
               let data = try? Data(contentsOf: fileURL) {
                photos.append((filename, data))
            }
        }
        return photos
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
