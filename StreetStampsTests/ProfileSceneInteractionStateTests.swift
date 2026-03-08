import XCTest
@testable import StreetStamps

final class ProfileSceneInteractionStateTests: XCTestCase {
    func test_myProfile_centersHostAndHidesWelcomeAndCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .myProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: false
        )

        XCTAssertEqual(state.hostSeat, .center)
        XCTAssertNil(state.visitorSeat)
        XCTAssertFalse(state.showsWelcomeBubble)
        XCTAssertFalse(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, nil)
    }

    func test_friendProfile_beforeSit_showsHostLeftWelcomeAndEnabledCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: false
        )

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertNil(state.visitorSeat)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertTrue(state.showsCTA)
        XCTAssertTrue(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "坐一坐")
    }

    func test_friendProfile_afterSit_showsVisitorRightAndDisablesCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: true,
            isInteractionInFlight: false
        )

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertEqual(state.visitorSeat, .right)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertTrue(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "已坐下")
        XCTAssertEqual(state.postcardPromptText, "send a postcard?")
    }

    func test_friendProfile_loading_usesLoadingCopy() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: true
        )

        XCTAssertTrue(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "坐下中...")
        XCTAssertNil(state.postcardPromptText)
    }

    func test_viewingOwnFriendProfile_hidesCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: true,
            isVisitorSeated: false,
            isInteractionInFlight: false
        )

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertNil(state.visitorSeat)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertFalse(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, nil)
        XCTAssertNil(state.postcardPromptText)
    }

    func test_friendProfile_beforeSit_hidesPostcardPrompt() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: false
        )

        XCTAssertNil(state.postcardPromptText)
    }
}
