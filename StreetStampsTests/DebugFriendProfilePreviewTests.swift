import XCTest
@testable import StreetStamps

final class DebugFriendProfilePreviewTests: XCTestCase {
    func test_fixtureProvidesUsableMockFriendProfile() {
        let fixture = DebugFriendProfilePreviewFixture.make()

        XCTAssertEqual(fixture.friend.displayName, "Mika Horizon")
        XCTAssertFalse(fixture.friend.handle.isEmpty)
        XCTAssertFalse(fixture.friend.bio.isEmpty)
        XCTAssertFalse(fixture.friend.journeys.isEmpty)
        XCTAssertFalse(fixture.friend.unlockedCityCards.isEmpty)
        XCTAssertGreaterThan(fixture.friend.stats.totalJourneys, 0)
        XCTAssertGreaterThan(fixture.friend.stats.totalMemories, 0)
        XCTAssertGreaterThan(fixture.friend.stats.totalUnlockedCities, 0)
    }

    func test_seatedPreviewStateShowsVisitorOnRightAndDisablesCTA() {
        let state = DebugFriendProfilePreviewState.seated.sceneState()

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertEqual(state.visitorSeat, .right)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertTrue(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "已坐下")
    }
}
