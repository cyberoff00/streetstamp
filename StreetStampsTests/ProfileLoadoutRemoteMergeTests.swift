import XCTest
@testable import StreetStamps

final class ProfileLoadoutRemoteMergeTests: XCTestCase {
    func test_staleRemoteLoadoutDoesNotOverridePendingLocalEdit() {
        let remote = makeLoadout("remote")
        let pending = makeLoadout("pending")

        let result = ProfileLoadoutRemoteMerge.resolve(
            remoteLoadout: remote,
            currentLocal: pending,
            lastSynced: remote,
            pendingLocal: pending
        )

        XCTAssertNil(result.appliedLoadout)
        XCTAssertEqual(result.lastSyncedLoadout, remote.normalizedForCurrentAvatar())
        XCTAssertEqual(result.pendingLocalLoadout, pending.normalizedForCurrentAvatar())
    }

    func test_matchingRemoteLoadoutClearsPendingLocalEdit() {
        let remote = makeLoadout("remote")

        let result = ProfileLoadoutRemoteMerge.resolve(
            remoteLoadout: remote,
            currentLocal: remote,
            lastSynced: makeLoadout("older"),
            pendingLocal: remote
        )

        XCTAssertEqual(result.appliedLoadout, remote.normalizedForCurrentAvatar())
        XCTAssertEqual(result.lastSyncedLoadout, remote.normalizedForCurrentAvatar())
        XCTAssertNil(result.pendingLocalLoadout)
    }

    func test_remoteLoadoutAppliesNormallyWithoutPendingEdit() {
        let remote = makeLoadout("remote")

        let result = ProfileLoadoutRemoteMerge.resolve(
            remoteLoadout: remote,
            currentLocal: makeLoadout("local"),
            lastSynced: nil,
            pendingLocal: nil
        )

        XCTAssertEqual(result.appliedLoadout, remote.normalizedForCurrentAvatar())
        XCTAssertEqual(result.lastSyncedLoadout, remote.normalizedForCurrentAvatar())
        XCTAssertNil(result.pendingLocalLoadout)
    }

    private func makeLoadout(_ token: String) -> RobotLoadout {
        RobotLoadout(
            hairId: "hair_\(token)",
            upperId: "upper_\(token)",
            underId: "under_\(token)",
            accessoryIds: ["hat_\(token)"],
            expressionId: "expr_\(token)"
        )
    }
}
