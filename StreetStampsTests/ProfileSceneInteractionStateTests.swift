import XCTest
@testable import StreetStamps

final class ProfileSceneInteractionStateTests: XCTestCase {
    private let englishStrings: [String: String] = [
        "friend_profile_cta_idle": "Take a seat",
        "friend_profile_cta_loading": "Sitting down...",
        "friend_profile_cta_done": "Seated",
        "friend_profile_cta_leave": "Get up",
        "friends_postcard_prompt": "bring you a postcard"
    ]

    private let simplifiedChineseStrings: [String: String] = [
        "friend_profile_cta_idle": "坐一坐",
        "friend_profile_cta_loading": "坐下中...",
        "friend_profile_cta_done": "已坐下",
        "friend_profile_cta_leave": "起身离开",
        "friends_postcard_prompt": "送你一张明信片"
    ]

    func test_myProfile_centersHostAndHidesWelcomeAndCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .myProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: false,
            localize: { self.englishStrings[$0] ?? $0 }
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
            isInteractionInFlight: false,
            localize: { self.englishStrings[$0] ?? $0 }
        )

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertNil(state.visitorSeat)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertTrue(state.showsCTA)
        XCTAssertTrue(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "Take a seat")
        XCTAssertEqual(state.ctaAction, .sit)
        XCTAssertFalse(state.showsPhotoBooth)
    }

    func test_friendProfile_afterSit_showsVisitorRightAndLeaveCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: true,
            isInteractionInFlight: false,
            localize: { self.englishStrings[$0] ?? $0 }
        )

        XCTAssertEqual(state.hostSeat, .left)
        XCTAssertEqual(state.visitorSeat, .right)
        XCTAssertTrue(state.showsWelcomeBubble)
        XCTAssertTrue(state.showsCTA)
        XCTAssertTrue(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "Get up")
        XCTAssertEqual(state.ctaAction, .leave)
        XCTAssertEqual(state.postcardPromptText, "bring you a postcard")
        XCTAssertTrue(state.showsPhotoBooth)
    }

    func test_friendProfile_loading_usesLoadingCopy() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: true,
            localize: { self.englishStrings[$0] ?? $0 }
        )

        XCTAssertTrue(state.showsCTA)
        XCTAssertFalse(state.isCTAEnabled)
        XCTAssertEqual(state.ctaTitle, "Sitting down...")
        XCTAssertNil(state.postcardPromptText)
    }

    func test_viewingOwnFriendProfile_hidesCTA() {
        let state = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: true,
            isVisitorSeated: false,
            isInteractionInFlight: false,
            localize: { self.englishStrings[$0] ?? $0 }
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
            isInteractionInFlight: false,
            localize: { self.englishStrings[$0] ?? $0 }
        )

        XCTAssertNil(state.postcardPromptText)
    }

    func test_friendProfile_cta_usesSimplifiedChineseCopy() {
        let seatedState = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: true,
            isInteractionInFlight: false,
            localize: { self.simplifiedChineseStrings[$0] ?? $0 }
        )
        let loadingState = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: true,
            localize: { self.simplifiedChineseStrings[$0] ?? $0 }
        )

        XCTAssertEqual(seatedState.ctaTitle, "起身离开")
        XCTAssertEqual(seatedState.postcardPromptText, "送你一张明信片")
        XCTAssertEqual(loadingState.ctaTitle, "坐下中...")
    }
}
