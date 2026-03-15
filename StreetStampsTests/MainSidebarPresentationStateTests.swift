import XCTest
@testable import StreetStamps

final class MainSidebarPresentationStateTests: XCTestCase {
    @MainActor
    func test_handleOpenDestination_promotesPendingEquipmentToActiveDestination() {
        var state = MainSidebarPresentationState()

        state.handleOpenDestinationSignal(pendingDestination: .equipment)

        XCTAssertEqual(state.activeDestination, .equipment)
    }

    @MainActor
    func test_handleOpenDestination_ignoresMissingPendingDestination() {
        var state = MainSidebarPresentationState()
        state.activeDestination = .profile

        state.handleOpenDestinationSignal(pendingDestination: nil)

        XCTAssertEqual(state.activeDestination, .profile)
    }

    @MainActor
    func test_dismiss_clearsActiveDestination() {
        var state = MainSidebarPresentationState()
        state.activeDestination = .equipment

        state.dismiss()

        XCTAssertNil(state.activeDestination)
    }
}
