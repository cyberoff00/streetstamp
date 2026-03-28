import XCTest
@testable import StreetStamps

final class EquipmentInteractionFeedbackPolicyTests: XCTestCase {
    func test_tryOnModeSelectingNewItemShowsTryingOnFeedback() {
        XCTAssertEqual(
            EquipmentInteractionFeedbackPolicy.feedbackLocalizationKey(
                isTryOnMode: true,
                tappedEquippedItem: false
            ),
            "equipment_trying_on"
        )
    }

    func test_tryOnModeUnequippingDoesNotShowTryingOnFeedback() {
        XCTAssertNil(
            EquipmentInteractionFeedbackPolicy.feedbackLocalizationKey(
                isTryOnMode: true,
                tappedEquippedItem: true
            )
        )
    }
}
