import XCTest
@testable import StreetStamps

@MainActor
final class SocialGraphStoreRestoreFriendsTests: XCTestCase {
    func test_restoreFriendsIfEmpty_restoresSnapshotsWhenCurrentListIsEmpty() {
        let defaultsKey = "social-graph-restore-\(UUID().uuidString)"
        let store = SocialGraphStore(userID: defaultsKey)
        let snapshot = FriendProfileSnapshot(
            id: "friend-1",
            handle: "friend.one",
            inviteCode: "ABCD1234",
            profileVisibility: .friendsOnly,
            displayName: "Friend One",
            bio: "",
            loadout: RobotLoadout.defaultBoy,
            stats: ProfileStatsSnapshot(),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date(timeIntervalSince1970: 1)
        )

        store.restoreFriendsIfEmpty([snapshot])

        XCTAssertEqual(store.friends, [snapshot])
    }

    func test_restoreFriendsIfEmpty_doesNotOverwriteNonEmptyList() {
        let defaultsKey = "social-graph-restore-\(UUID().uuidString)"
        let store = SocialGraphStore(userID: defaultsKey)
        let existing = FriendProfileSnapshot(
            id: "friend-1",
            handle: "friend.one",
            inviteCode: "ABCD1234",
            profileVisibility: .friendsOnly,
            displayName: "Friend One",
            bio: "",
            loadout: RobotLoadout.defaultBoy,
            stats: ProfileStatsSnapshot(),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let fallback = FriendProfileSnapshot(
            id: "friend-2",
            handle: "friend.two",
            inviteCode: "WXYZ5678",
            profileVisibility: .friendsOnly,
            displayName: "Friend Two",
            bio: "",
            loadout: RobotLoadout.defaultGirl,
            stats: ProfileStatsSnapshot(),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date(timeIntervalSince1970: 2)
        )

        store.importFriendSnapshot(existing)
        store.restoreFriendsIfEmpty([fallback])

        XCTAssertEqual(store.friends, [existing])
    }
}
