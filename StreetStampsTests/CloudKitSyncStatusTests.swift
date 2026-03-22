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
}
