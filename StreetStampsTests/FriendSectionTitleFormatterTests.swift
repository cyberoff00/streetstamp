import XCTest
@testable import StreetStamps

final class FriendSectionTitleFormatterTests: XCTestCase {
    func test_titlesUseLocalizedEnglishLabels() {
        let locale = Locale(identifier: "en")

        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeys, friendName: "Alex", locale: locale),
            "Alex · Journeys"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .cityCards, friendName: "Alex", locale: locale),
            "Alex · City Cards"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeyMemories, friendName: "Alex", locale: locale),
            "Alex · Journey Memory"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeyDetail, friendName: "Alex", locale: locale),
            "Alex · Journey"
        )
    }

    func test_titlesUseLocalizedSimplifiedChineseLabels() {
        let locale = Locale(identifier: "zh-Hans")

        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeys, friendName: "小李", locale: locale),
            "小李 · 旅程"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .cityCards, friendName: "小李", locale: locale),
            "小李 · 城市卡"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeyMemories, friendName: "小李", locale: locale),
            "小李 · 旅程记忆"
        )
        XCTAssertEqual(
            FriendSectionTitleFormatter.sectionTitle(for: .journeyDetail, friendName: "小李", locale: locale),
            "小李 · 旅程"
        )
    }
}
