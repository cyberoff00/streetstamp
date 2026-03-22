import XCTest

final class ProfileScannerSourceParityTests: XCTestCase {
    func test_profileScannerSheetSupportsImportingQRCodeFromPhotoLibrary() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("@State private var pickedPhotoItem: PhotosPickerItem?"))
        XCTAssertTrue(contents.contains("@State private var isImportingFromAlbum = false"))
        XCTAssertTrue(contents.contains("@State private var showPhotoPicker = false"))
        XCTAssertTrue(contents.contains("QRCodeImageDecoder.decode(image: image)"))
        XCTAssertTrue(contents.contains(".photosPicker(isPresented: $showPhotoPicker"))
        XCTAssertTrue(contents.contains("friends_qr_import_from_album"))
        XCTAssertTrue(contents.contains("friends_qr_not_detected"))
    }
}
