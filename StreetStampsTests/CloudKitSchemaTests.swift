import XCTest
@testable import StreetStamps

final class CloudKitSchemaTests: XCTestCase {
    func test_recordTypes_match_incremental_sync_domains() {
        XCTAssertEqual(CloudKitRecordType.journey, "Journey")
        XCTAssertEqual(CloudKitRecordType.journeyMemory, "JourneyMemory")
        XCTAssertEqual(CloudKitRecordType.photo, "Photo")
        XCTAssertEqual(CloudKitRecordType.passiveLifelogBatch, "PassiveLifelogBatch")
        XCTAssertEqual(CloudKitRecordType.lifelogMood, "LifelogMood")
        XCTAssertEqual(CloudKitRecordType.settings, "Settings")
    }

    func test_legacy_snapshot_or_cache_record_types_are_not_primary_sync_domains() {
        let recordTypes = [
            CloudKitRecordType.journey,
            CloudKitRecordType.journeyMemory,
            CloudKitRecordType.photo,
            CloudKitRecordType.passiveLifelogBatch,
            CloudKitRecordType.lifelogMood,
            CloudKitRecordType.settings
        ]

        XCTAssertFalse(recordTypes.contains("LifelogBatch"))
        XCTAssertFalse(recordTypes.contains("CityCache"))
    }
}
