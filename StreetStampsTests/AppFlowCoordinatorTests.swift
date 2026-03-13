import XCTest
@testable import StreetStamps

final class AppFlowCoordinatorTests: XCTestCase {
    @MainActor
    func testRequestOpenPostcardSidebarStoresIntentAndIncrementsSignal() {
        let coordinator = AppFlowCoordinator()

        coordinator.requestOpenPostcardSidebar(
            PostcardInboxIntent(box: "received", messageID: "pm_123")
        )

        XCTAssertEqual(coordinator.openPostcardSidebarSignal, 1)
        XCTAssertEqual(
            coordinator.pendingPostcardSidebarIntent,
            PostcardInboxIntent(box: "received", messageID: "pm_123")
        )
    }

    @MainActor
    func testConsumePendingPostcardSidebarClearsIntent() {
        let coordinator = AppFlowCoordinator()
        coordinator.requestOpenPostcardSidebar(
            PostcardInboxIntent(box: "received", messageID: "pm_123")
        )

        coordinator.consumePendingPostcardSidebarIntent()

        XCTAssertNil(coordinator.pendingPostcardSidebarIntent)
        XCTAssertEqual(coordinator.openPostcardSidebarSignal, 1)
    }

    @MainActor
    func testRequestOpenSidebarDestinationStoresDestinationAndIncrementsSignal() {
        let coordinator = AppFlowCoordinator()

        coordinator.requestOpenSidebarDestination(.equipment)

        XCTAssertEqual(coordinator.openSidebarDestinationSignal, 1)
        XCTAssertEqual(coordinator.pendingSidebarDestination, .equipment)
    }

    @MainActor
    func testConsumePendingSidebarDestinationClearsDestination() {
        let coordinator = AppFlowCoordinator()
        coordinator.requestOpenSidebarDestination(.accountCenter)

        coordinator.consumePendingSidebarDestination()

        XCTAssertNil(coordinator.pendingSidebarDestination)
        XCTAssertEqual(coordinator.openSidebarDestinationSignal, 1)
    }
}
