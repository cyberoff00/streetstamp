import XCTest

final class ProfilePostcardSectionSourceParityTests: XCTestCase {
    func test_profileAndFriendScreensUseSharedPostcardEntryCard() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let profileContents = try String(
            contentsOf: root.appendingPathComponent("ProfileView.swift"),
            encoding: .utf8
        )
        let friendContents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(profileContents.contains("ProfilePostcardEntryCard("))
        XCTAssertTrue(friendContents.contains("ProfilePostcardEntryCard("))
    }

    func test_compactActivityCardKeepsHeatmapAndDetachedStatsCardLayout() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("CompactActivityRingCard.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("MiniJourneyHeatmap"))
        XCTAssertTrue(contents.contains("activityPanel"))
        XCTAssertTrue(contents.contains("statsPanel"))
        XCTAssertTrue(contents.contains("progressRing"))
    }

    func test_profilePostcardSurfacesUseSharedThemePrimaryAccent() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let postcardContents = try String(
            contentsOf: root.appendingPathComponent("ProfilePostcardEntryCard.swift"),
            encoding: .utf8
        )
        let activityContents = try String(
            contentsOf: root.appendingPathComponent("CompactActivityRingCard.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(postcardContents.contains("FigmaTheme.primary"))
        XCTAssertTrue(activityContents.contains("FigmaTheme.primary"))
        XCTAssertFalse(postcardContents.contains("Color(red: 0.27, green: 0.50, blue: 0.95)"))
        XCTAssertFalse(activityContents.contains("Color(red: 0.27, green: 0.50, blue: 0.95)"))
    }

    func test_customTabBarDoesNotKeepLegacyBottomSpacerPadding() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("MainTab.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertFalse(contents.contains(".padding(.bottom, 34)"))
    }

    func test_profileHeroBackdropUsesSharedSceneBackgroundTint() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let contents = try String(
            contentsOf: root.appendingPathComponent("ProfileHeroComponents.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("Color(red: 224.0 / 255.0, green: 241.0 / 255.0, blue: 237.0 / 255.0)"))
    }

    func test_profileAndFriendHeroesUseSharedActivitySummarySection() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let profileContents = try String(
            contentsOf: root.appendingPathComponent("ProfileView.swift"),
            encoding: .utf8
        )
        let friendContents = try String(
            contentsOf: root.appendingPathComponent("FriendsHubView.swift"),
            encoding: .utf8
        )
        let sharedContents = try String(
            contentsOf: root.appendingPathComponent("ProfileHeroActivitySummarySection.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(profileContents.contains("ProfileHeroActivitySummarySection("))
        XCTAssertTrue(friendContents.contains("ProfileHeroActivitySummarySection("))
        XCTAssertTrue(sharedContents.contains("MiniJourneyHeatmap"))
        XCTAssertTrue(sharedContents.contains("concentricRings"))
        XCTAssertTrue(sharedContents.contains("UserLevelProgress"))
        XCTAssertTrue(sharedContents.contains("Rectangle()"))
    }
}
