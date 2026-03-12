import XCTest
@testable import StreetStamps

final class ICloudSyncDefaultsSnapshotTests: XCTestCase {
    func test_filteredValues_includeUserSettingsAndExcludeSessionSecrets() {
        let source: [String: Any] = [
            "streetstamps.profile.displayName": "Explorer",
            "streetstamps.voice.broadcast.enabled": true,
            "streetstamps.session.v1": Data([0x00, 0x01]),
            "streetstamps.firebase_account_state.v1": Data([0x02]),
            "streetstamps.pending_guest_migration.v1": "guest_1",
            "unrelated.key": "ignored"
        ]

        let filtered = ICloudSyncDefaultsSnapshot.filteredValues(from: source)

        XCTAssertEqual(filtered["streetstamps.profile.displayName"] as? String, "Explorer")
        XCTAssertEqual(filtered["streetstamps.voice.broadcast.enabled"] as? Bool, true)
        XCTAssertNil(filtered["streetstamps.session.v1"])
        XCTAssertNil(filtered["streetstamps.firebase_account_state.v1"])
        XCTAssertNil(filtered["streetstamps.pending_guest_migration.v1"])
        XCTAssertNil(filtered["unrelated.key"])
    }
}
