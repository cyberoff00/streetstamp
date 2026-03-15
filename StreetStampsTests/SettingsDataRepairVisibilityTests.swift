import XCTest
@testable import StreetStamps

final class SettingsDataRepairVisibilityTests: XCTestCase {
    func test_isAvailable_returnsTrueForRegularReleaseReceipt() {
        XCTAssertTrue(SettingsDataRepairVisibility.isAvailable(receiptLastPathComponent: "receipt"))
    }

    func test_isAvailable_returnsTrueWhenReceiptIsMissing() {
        XCTAssertTrue(SettingsDataRepairVisibility.isAvailable(receiptLastPathComponent: nil))
    }
}
