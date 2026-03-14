import XCTest
@testable import StreetStamps

final class FirstProfileSetupViewModelTests: XCTestCase {
    func test_minimalPresentationMatchesApprovedSetupCopy() {
        let presentation = FirstProfileSetupPresentationModel.minimal

        XCTAssertEqual(presentation.heroTitleKey, "profile_setup_avatar_title")
        XCTAssertEqual(presentation.heroHelperKey, "profile_setup_avatar_hint")
        XCTAssertFalse(presentation.showsSubtitle)
        XCTAssertFalse(presentation.showsNicknameHint)
        XCTAssertFalse(presentation.showsSummaryCard)
    }

    func test_primaryActionsUseFullSurfaceHitTargets() {
        let presentation = FirstProfileSetupPresentationModel.minimal

        XCTAssertTrue(presentation.skipAction.usesFullSurfaceHitTarget)
        XCTAssertTrue(presentation.editLookAction.usesFullSurfaceHitTarget)
        XCTAssertTrue(presentation.confirmAction.usesFullSurfaceHitTarget)
    }

    func test_minimalPresentationUsesSingleVisibleTitleAndRaisedSkipButton() {
        let presentation = FirstProfileSetupPresentationModel.minimal

        XCTAssertFalse(presentation.showsHeroCardTitle)
        XCTAssertTrue(presentation.usesScrollLayout)
        XCTAssertEqual(presentation.contentOrder, [.nickname, .avatar])
        XCTAssertEqual(presentation.skipButtonTopOffset, -6)
    }

    func test_debugPreviewSkipWithoutTokenDismissesImmediately() {
        XCTAssertTrue(
            FirstProfileSetupDebugPreviewBehavior.shouldDismissImmediately(
                for: .skip,
                isDebugPreview: true,
                hasAccessToken: false
            )
        )
        XCTAssertFalse(
            FirstProfileSetupDebugPreviewBehavior.shouldDismissImmediately(
                for: .confirm,
                isDebugPreview: true,
                hasAccessToken: false
            )
        )
        XCTAssertFalse(
            FirstProfileSetupDebugPreviewBehavior.shouldDismissImmediately(
                for: .skip,
                isDebugPreview: false,
                hasAccessToken: false
            )
        )
    }
}
