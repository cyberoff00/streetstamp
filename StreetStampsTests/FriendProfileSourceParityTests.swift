import XCTest

final class FriendProfileSourceParityTests: XCTestCase {
    func test_mainViewUsesLocalizedStringResolutionForJourneyCta() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("MainView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains(#"Text(L10n.t("main_unlock_new_journey"))"#))
        XCTAssertFalse(contents.contains(#"Text(L10n.key("main_unlock_new_journey"))"#))
    }

    func test_lifelogViewLocalizesStepModalSummaryCopy() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("LifelogView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains(#"Text(String(format: L10n.t("lifelog_steps_modal_summary_format"), formattedStepCount(stepModalStepCount)))"#))
        XCTAssertFalse(contents.contains(#"Text("今天你在地球上又留下了 \(formattedStepCount(stepModalStepCount)) 步足迹")"#))
    }

    func test_friendProfileScreen_routesTileButtonsThroughNavigationDestination() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("@State private var activeRoute: FriendsRoute?"))
        XCTAssertTrue(contents.contains("activeRoute.wrappedValue = .cities(friendID)"))
        XCTAssertTrue(contents.contains("activeRoute.wrappedValue = .publicMemories(friendID)"))
        XCTAssertTrue(contents.contains(".navigationDestination(item: $activeRoute) { route in"))
        XCTAssertTrue(contents.contains("switch route {"))
        XCTAssertTrue(contents.contains("case .cities(let friendID):"))
        XCTAssertTrue(contents.contains("FriendCitiesScreen(friendID: friendID)"))
        XCTAssertTrue(contents.contains("case .publicMemories(let friendID):"))
        XCTAssertTrue(contents.contains("FriendPublicMemoriesScreen(friendID: friendID)"))
        XCTAssertFalse(contents.contains("case .equipment(let friendID):"))
        XCTAssertFalse(contents.contains("FriendEquipmentScreen(friendID: friendID)"))
    }

    func test_friendRoutes_preserveSnapshotFallbackForDetailScreens() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("case journey(friendID: String, snapshot: FriendProfileSnapshot?, journeyID: String)"))
        XCTAssertTrue(contents.contains("activeRoute = .journey(friendID: friend.id, snapshot: friend, journeyID: jid)"))
        XCTAssertTrue(contents.contains("FriendJourneyRouteScreen(friendID: friendID, fallbackSnapshot: snapshot, journeyID: journeyID)"))
        XCTAssertTrue(contents.contains("private let fallbackSnapshot: FriendProfileSnapshot?"))
        XCTAssertTrue(contents.contains("socialStore.friends.first(where: { $0.id == friendID }) ?? fallbackSnapshot"))
    }

    func test_activityFeedUsesPromptRefreshAndScrollRestoreFlow() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("@State private var pendingFeedRefreshProfiles: [FriendProfileSnapshot]?"))
        XCTAssertTrue(contents.contains("@State private var feedScrollRestoreState = FriendsFeedScrollRestoreState()"))
        XCTAssertTrue(contents.contains("await detectUnseenFeedUpdates()"))
        XCTAssertFalse(contents.contains("try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)\n                await refreshRemoteFriends()"))
        XCTAssertTrue(contents.contains("Text(L10n.t(\"friends_feed_new_activity_prompt\"))"))
        XCTAssertTrue(contents.contains("ScrollViewReader { proxy in"))
        XCTAssertTrue(contents.contains("feedScrollRestoreState.recordOpen(eventID: event.id)"))
        XCTAssertTrue(contents.contains("proxy.scrollTo(eventID, anchor: .center)"))
    }

    func test_friendProfileSourceAvoidsHardcodedEnglishUserFacingCopy() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(contents.contains(#""%.1f km""#))
        XCTAssertFalse(contents.contains(#""\(friend.displayName) Equipment""#))
        XCTAssertFalse(contents.contains(#"return "None""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Hair""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Upper""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Under""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Hat""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Glasses""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Accessory""#))
        XCTAssertFalse(contents.contains(#"FriendEquipmentRow(title: "Expression""#))
        XCTAssertTrue(contents.contains(#"L10n.t("friends_distance_compact_format")"#))
        XCTAssertFalse(contents.contains("FriendEquipmentScreen"))
        XCTAssertFalse(contents.contains("FriendEquipmentRow"))
    }

    func test_friendProfileHeroMetaRowShowsJoinDateWithoutDistance() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(contents.contains(#"Text(String(format: L10n.t("friends_distance_compact_format"), max(0, friend.stats.totalDistance / 1000.0)))"#))
        XCTAssertFalse(contents.contains(#"Image(systemName: "mappin.and.ellipse")"#))
        XCTAssertFalse(contents.contains(#"Text("•")"#))
        XCTAssertTrue(contents.contains(#"Text(String(format: L10n.t("friends_joined_format"), heroJoinedDateText(friend.createdAt)))"#))
    }
}
