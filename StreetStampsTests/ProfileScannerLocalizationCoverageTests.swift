import XCTest
@testable import StreetStamps

final class ProfileScannerLocalizationCoverageTests: XCTestCase {
    func test_profileScannerPhotoImportKeysExistInEnglishAndSimplifiedChinese() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        let keys = [
            "friends_qr_importing",
            "friends_qr_import_from_album",
            "friends_qr_read_failed",
            "friends_qr_not_detected"
        ]

        for key in keys {
            XCTAssertNotNil(english[key], "Missing English localization for key \(key)")
            XCTAssertNotNil(simplifiedChinese[key], "Missing Simplified Chinese localization for key \(key)")
        }
    }
}
