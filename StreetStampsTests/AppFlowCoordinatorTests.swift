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
    func testRequestModalPushStoresDestinationAndIncrementsSignal() {
        let coordinator = AppFlowCoordinator()

        coordinator.requestModalPush(.equipment)

        XCTAssertEqual(coordinator.openModalDestinationSignal, 1)
        XCTAssertEqual(coordinator.pendingModalDestination, .equipment)
    }

    @MainActor
    func testConsumePendingModalDestinationClearsDestination() {
        let coordinator = AppFlowCoordinator()
        coordinator.requestModalPush(.equipment)

        coordinator.consumePendingModalDestination()

        XCTAssertNil(coordinator.pendingModalDestination)
        XCTAssertEqual(coordinator.openModalDestinationSignal, 1)
    }
}
