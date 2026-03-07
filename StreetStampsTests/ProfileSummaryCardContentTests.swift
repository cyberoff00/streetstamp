import XCTest
@testable import StreetStamps

final class ProfileSummaryCardContentTests: XCTestCase {
    func test_levelTextShowsOnlyLevel() {
        let content = ProfileSummaryCardContent(level: 7, cityCount: 12, memoryCount: 34)

        XCTAssertEqual(content.levelText, "Lv.7")
    }

    func test_statsTextShowsOnlyCitiesAndMemories() {
        let content = ProfileSummaryCardContent(level: 3, cityCount: 5, memoryCount: 18)

        XCTAssertEqual(content.statsText, "5 Cities  18 Memories")
    }
}
