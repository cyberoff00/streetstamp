import XCTest
@testable import StreetStamps

final class NavigationChromePolicyTests: XCTestCase {
    func test_primarySidebarDestinations_remainAccountAndUtilitySections() {
        let destinations = MainSidebarDestination.primaryDestinations

        XCTAssertEqual(destinations, [.profile, .equipment, .settings])
    }

    func test_quickActions_includePostcardsAndInviteFriend() {
        XCTAssertEqual(MainSidebarDestination.quickActions, [.postcards, .inviteFriend])
    }

    func test_primarySidebarDestinations_doNotAddBackNavigationRequirements() {
        XCTAssertEqual(MainSidebarDestination.profile.navigationChrome.leadingAccessory, .none)
        XCTAssertEqual(MainSidebarDestination.settings.navigationChrome.leadingAccessory, .none)
        XCTAssertEqual(MainSidebarDestination.equipment.navigationChrome.leadingAccessory, .none)
    }

    func test_quickActionDestinations_useBackLeadingAccessory() {
        XCTAssertEqual(MainSidebarDestination.postcards.navigationChrome.leadingAccessory, .back)
        XCTAssertEqual(MainSidebarDestination.inviteFriend.navigationChrome.leadingAccessory, .back)
    }
}
