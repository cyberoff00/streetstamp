import XCTest
@testable import StreetStamps

final class MainTabLayoutTests: XCTestCase {
    func test_bottomTabs_matchRequestedOrder() {
        XCTAssertEqual(
            MainTabLayout.bottomTabs.map(\.tab),
            [.start, .memory, .cities, .lifelog, .friends]
        )
    }

    func test_bottomTabs_swapStartAndLifelogIconsOnly() {
        let iconsByTab = Dictionary(uniqueKeysWithValues: MainTabLayout.bottomTabs.map { ($0.tab, $0.systemImage) })

        XCTAssertEqual(iconsByTab[.start], "point.bottomleft.forward.to.point.topright.scurvepath")
        XCTAssertEqual(iconsByTab[.lifelog], "house.fill")
        XCTAssertEqual(iconsByTab[.memory], "heart.fill")
        XCTAssertEqual(iconsByTab[.cities], "square.grid.2x2.fill")
        XCTAssertEqual(iconsByTab[.friends], "person.2.fill")
    }
}
