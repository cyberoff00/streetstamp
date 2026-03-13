import XCTest
@testable import StreetStamps

final class AppSettingsICloudSyncTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudSyncEnabledKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudAutomaticRestoreEnabledKey)
    }

    func test_iCloudSyncEnabled_defaultsToTrueWhenUnset() {
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudSyncEnabledKey)

        XCTAssertTrue(AppSettings.isICloudSyncEnabled)
    }

    func test_iCloudSyncEnabled_respectsStoredFalseValue() {
        UserDefaults.standard.set(false, forKey: AppSettings.iCloudSyncEnabledKey)

        XCTAssertFalse(AppSettings.isICloudSyncEnabled)
    }

    func test_automaticICloudRestore_defaultsToFalseWhenUnset() {
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudAutomaticRestoreEnabledKey)

        XCTAssertFalse(AppSettings.isAutomaticICloudRestoreEnabled)
    }

    func test_automaticICloudRestore_respectsStoredTrueValue() {
        UserDefaults.standard.set(true, forKey: AppSettings.iCloudAutomaticRestoreEnabledKey)

        XCTAssertTrue(AppSettings.isAutomaticICloudRestoreEnabled)
    }
}
