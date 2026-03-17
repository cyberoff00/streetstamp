import XCTest
@testable import StreetStamps

final class MainTabLayoutTests: XCTestCase {
    func test_bottomTabs_matchRequestedOrder() {
        XCTAssertEqual(
            MainTabLayout.bottomTabs.map(\.tab),
            [.start, .cities, .lifelog, .friends, .profile]
        )
    }

    func test_bottomTabs_useFigmaAssetIconsForEachTab() {
        let iconsByTab = Dictionary(uniqueKeysWithValues: MainTabLayout.bottomTabs.map { ($0.tab, $0.icon) })

        XCTAssertEqual(iconsByTab[.start], .asset("tab_lifelog_icon"))
        XCTAssertEqual(iconsByTab[.cities], .asset("tab_memory_icon"))
        XCTAssertEqual(iconsByTab[.lifelog], .asset("tab_cities_icon"))
        XCTAssertEqual(iconsByTab[.friends], .asset("tab_friends_icon"))
        XCTAssertEqual(iconsByTab[.profile], .system("person"))
    }
}
