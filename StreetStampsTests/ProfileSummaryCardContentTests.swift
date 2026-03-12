import XCTest
@testable import StreetStamps

final class ProfileSummaryCardContentTests: XCTestCase {
    func test_levelTextShowsOnlyLevel() {
        let content = ProfileSummaryCardContent(level: 7, cityCount: 12, memoryCount: 34)

        XCTAssertEqual(content.levelText, "Lv.7")
    }

    func test_statsTextShowsOnlyCitiesAndMemoriesInEnglish() {
        let content = ProfileSummaryCardContent(level: 3, cityCount: 5, memoryCount: 18, locale: Locale(identifier: "en"))

        XCTAssertEqual(content.statsText, "5 Cities  18 Memories")
    }

    func test_statsTextUsesLocalizedChineseLabels() {
        let content = ProfileSummaryCardContent(level: 3, cityCount: 5, memoryCount: 18, locale: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(content.statsText, "5 城市  18 记忆")
    }
}
