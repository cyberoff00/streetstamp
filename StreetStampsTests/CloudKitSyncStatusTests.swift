import XCTest
@testable import StreetStamps

final class CloudKitSyncStatusTests: XCTestCase {
    func test_statusKeys_useSharedICloudStatusNamespace() {
        let userID = "user-123"

        XCTAssertEqual(
            CloudKitSyncService.statusKey(for: userID),
            "streetstamps.icloud.sync.status.user-123"
        )
        XCTAssertEqual(
            CloudKitSyncService.statusAtKey(for: userID),
            "streetstamps.icloud.sync.status_at.user-123"
        )
    }

    func test_restoreResult_totalCountAddsJourneyAndLifelogCounts() {
        let result = CloudKitRestoreResult(
            restoredJourneyCount: 3,
            restoredLifelogCount: 5
        )

        XCTAssertEqual(result.totalCount, 8)
    }

    func test_statusSnapshot_prefersAccountStatusAndFallsBackToLocalProfile() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let localUserID = "local_123"
        let accountUserID = "account_456"
        let localDate = Date(timeIntervalSince1970: 100)
        let accountDate = Date(timeIntervalSince1970: 200)

        defaults.set("restore_success", forKey: CloudKitSyncService.statusKey(for: localUserID))
        defaults.set(localDate, forKey: CloudKitSyncService.statusAtKey(for: localUserID))
        defaults.set("restore_partial", forKey: CloudKitSyncService.statusKey(for: accountUserID))
        defaults.set(accountDate, forKey: CloudKitSyncService.statusAtKey(for: accountUserID))

        let preferred = CloudKitSyncService.statusSnapshot(
            defaults: defaults,
            localUserID: localUserID,
            accountUserID: accountUserID
        )
        XCTAssertEqual(preferred.status, "restore_partial")
        XCTAssertEqual(preferred.at, accountDate)

        defaults.removeObject(forKey: CloudKitSyncService.statusKey(for: accountUserID))
        defaults.removeObject(forKey: CloudKitSyncService.statusAtKey(for: accountUserID))

        let fallback = CloudKitSyncService.statusSnapshot(
            defaults: defaults,
            localUserID: localUserID,
            accountUserID: accountUserID
        )
        XCTAssertEqual(fallback.status, "restore_success")
        XCTAssertEqual(fallback.at, localDate)
    }
}
