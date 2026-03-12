import XCTest
@testable import StreetStamps

final class AppSettingsICloudSyncTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudSyncEnabledKey)
    }

    func test_iCloudSyncEnabled_defaultsToTrueWhenUnset() {
        UserDefaults.standard.removeObject(forKey: AppSettings.iCloudSyncEnabledKey)

        XCTAssertTrue(AppSettings.isICloudSyncEnabled)
    }

    func test_iCloudSyncEnabled_respectsStoredFalseValue() {
        UserDefaults.standard.set(false, forKey: AppSettings.iCloudSyncEnabledKey)

        XCTAssertFalse(AppSettings.isICloudSyncEnabled)
    }
}
