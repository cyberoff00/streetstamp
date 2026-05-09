import XCTest
@testable import StreetStamps

/// Cross-device loadout sync must avoid clobbering a fresher local loadout with
/// a stale cloud upload. CloudKitSyncService.mergeLoadoutByModifiedAt resolves
/// that decision by comparing per-record `modifiedAt`. These tests pin the
/// decision matrix.
final class LoadoutCloudKitMergeTests: XCTestCase {
    func test_remoteWinsWhenItIsNewer() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: Date(timeIntervalSince1970: 1_000))
        let remote = stamped("remote", at: Date(timeIntervalSince1970: 2_000))
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, remote.hairId)
    }

    func test_localKeptWhenItIsNewer() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: Date(timeIntervalSince1970: 2_000))
        let remote = stamped("remote", at: Date(timeIntervalSince1970: 1_000))
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, local.hairId)
    }

    func test_localKeptWhenRemoteHasNoTimestamp() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: Date(timeIntervalSince1970: 2_000))
        let remote = stamped("remote", at: nil)
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, local.hairId)
    }

    func test_remoteAppliedWhenLocalHasNoTimestamp() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: nil)
        let remote = stamped("remote", at: Date(timeIntervalSince1970: 1_000))
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, remote.hairId)
    }

    func test_remoteAppliedWhenNoLocalLoadoutExists() throws {
        let defaults = try makeDefaults()
        let remote = stamped("remote", at: Date(timeIntervalSince1970: 1_000))

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, remote.hairId)
    }

    func test_remoteAppliedWhenBothLackTimestamps_legacyFallback() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: nil)
        let remote = stamped("remote", at: nil)
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        // First-migration behavior: no timestamps anywhere → defer to cloud,
        // matching the pre-timestamp overwrite path so existing accounts don't
        // suddenly diverge across devices.
        XCTAssertEqual(try decodeLoadout(defaults).hairId, remote.hairId)
    }

    func test_overwritePropagatesToActiveUserScopedKey() throws {
        let defaults = try makeDefaults()
        let userID = "account_xyz"
        defaults.set(userID, forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)

        let local = stamped("local", at: Date(timeIntervalSince1970: 1_000))
        let remote = stamped("remote", at: Date(timeIntervalSince1970: 2_000))
        try writeLoadout(local, to: defaults)
        defaults.set(
            try JSONEncoder().encode(local),
            forKey: UserScopedProfileStateStore.avatarLoadoutKey(for: userID)
        )

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: try JSONEncoder().encode(remote),
            defaults: defaults
        )

        let scopedData = try XCTUnwrap(
            defaults.data(forKey: UserScopedProfileStateStore.avatarLoadoutKey(for: userID))
        )
        let scoped = try JSONDecoder().decode(RobotLoadout.self, from: scopedData)
        XCTAssertEqual(scoped.hairId, remote.hairId)
    }

    func test_invalidRemotePayloadIsIgnored() throws {
        let defaults = try makeDefaults()
        let local = stamped("local", at: Date(timeIntervalSince1970: 1_000))
        try writeLoadout(local, to: defaults)

        CloudKitSyncService.mergeLoadoutByModifiedAt(
            remoteValue: Data([0xFF, 0xFE]),
            defaults: defaults
        )

        XCTAssertEqual(try decodeLoadout(defaults).hairId, local.hairId)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let suite = "LoadoutCloudKitMergeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw XCTSkip("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func stamped(_ token: String, at date: Date?) -> RobotLoadout {
        var loadout = RobotLoadout(
            hairId: "hair_\(token)",
            upperId: "upper_\(token)",
            underId: "under_\(token)",
            expressionId: "expr_\(token)"
        )
        loadout.modifiedAt = date
        return loadout
    }

    private func writeLoadout(_ loadout: RobotLoadout, to defaults: UserDefaults) throws {
        defaults.set(
            try JSONEncoder().encode(loadout),
            forKey: UserScopedProfileStateStore.globalAvatarLoadoutKey
        )
    }

    private func decodeLoadout(_ defaults: UserDefaults) throws -> RobotLoadout {
        let data = try XCTUnwrap(defaults.data(forKey: UserScopedProfileStateStore.globalAvatarLoadoutKey))
        return try JSONDecoder().decode(RobotLoadout.self, from: data)
    }
}
