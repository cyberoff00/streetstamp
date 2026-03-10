import XCTest
@testable import StreetStamps

final class MainTabLayoutTests: XCTestCase {
    func test_bottomTabs_matchRequestedOrder() {
        XCTAssertEqual(
            MainTabLayout.bottomTabs.map(\.tab),
            [.start, .memory, .cities, .lifelog, .friends]
        )
    }

    func test_bottomTabs_useFigmaAssetIconsForEachTab() {
        let iconsByTab = Dictionary(uniqueKeysWithValues: MainTabLayout.bottomTabs.map { ($0.tab, $0.iconAssetName) })

        XCTAssertEqual(iconsByTab[.start], "tab_start_icon")
        XCTAssertEqual(iconsByTab[.memory], "tab_memory_icon")
        XCTAssertEqual(iconsByTab[.cities], "tab_cities_icon")
        XCTAssertEqual(iconsByTab[.lifelog], "tab_lifelog_icon")
        XCTAssertEqual(iconsByTab[.friends], "tab_friends_icon")
    }
}
