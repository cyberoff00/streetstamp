import XCTest
@testable import StreetStamps

final class LifelogStepMilestonePresentationTests: XCTestCase {
    func test_stepMilestoneModal_supportsBackdropDismiss() {
        XCTAssertTrue(LifelogStepMilestonePresentation.supportsBackdropDismiss)
    }

    func test_stepMilestoneModal_hidesFooterCloseButton() {
        XCTAssertFalse(LifelogStepMilestonePresentation.showsFooterCloseButton)
    }

    func test_stepMilestoneModal_placesCloseButtonTopTrailing() {
        XCTAssertEqual(
            LifelogStepMilestonePresentation.closeButtonPlacement,
            .topTrailing
        )
    }

    func test_stepMilestoneModal_hidesCelebrationHeadline() {
        XCTAssertFalse(LifelogStepMilestonePresentation.showsCelebrationHeadline)
    }

    func test_stepMilestoneModal_usesCompactTopPadding() {
        XCTAssertEqual(LifelogStepMilestonePresentation.topPadding, 14)
    }
}
