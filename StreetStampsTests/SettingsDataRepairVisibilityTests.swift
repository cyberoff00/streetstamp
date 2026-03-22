import XCTest
@testable import StreetStamps

final class SettingsDataRepairVisibilityTests: XCTestCase {
    func test_isAvailable_returnsTrueForRegularReleaseReceipt() {
        XCTAssertTrue(SettingsDataRepairVisibility.isAvailable(receiptLastPathComponent: "receipt"))
    }

    func test_isAvailable_returnsTrueWhenReceiptIsMissing() {
        XCTAssertTrue(SettingsDataRepairVisibility.isAvailable(receiptLastPathComponent: nil))
    }

    func test_settingsRepairSource_rebuildsCityCacheFromJourneyStoreAfterRepair() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/SettingsView+DataRepair.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("await journeyStore.loadAsync()"))
        XCTAssertTrue(source.contains("cityCache.rebuildFromJourneyStore()"))
    }

    func test_manualRepairSource_noLongerWritesLegacyCityCacheSnapshot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/ManualDeviceRepairService.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertFalse(source.contains("CityNameRepairService.rebuildCityCache"))
    }
}
