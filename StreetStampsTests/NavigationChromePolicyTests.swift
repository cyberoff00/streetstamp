import XCTest
@testable import StreetStamps

final class NavigationChromePolicyTests: XCTestCase {
    func test_primaryModalDestinations_remainAccountAndUtilitySections() {
        let destinations = ModalNavDestination.primaryDestinations

        XCTAssertEqual(destinations, [.profile, .equipment, .settings])
    }

    func test_quickActions_includeInviteFriend() {
        XCTAssertEqual(ModalNavDestination.quickActions, [.inviteFriend])
    }

    func test_primaryModalDestinations_doNotAddBackNavigationRequirements() {
        XCTAssertEqual(ModalNavDestination.profile.navigationChrome.leadingAccessory, .none)
        XCTAssertEqual(ModalNavDestination.settings.navigationChrome.leadingAccessory, .none)
        XCTAssertEqual(ModalNavDestination.equipment.navigationChrome.leadingAccessory, .none)
    }

    func test_quickActionDestinations_useBackLeadingAccessory() {
        XCTAssertEqual(ModalNavDestination.inviteFriend.navigationChrome.leadingAccessory, .back)
    }
}
