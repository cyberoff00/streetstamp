import XCTest

final class FriendLocalizationCopyTests: XCTestCase {
    func test_friendSectionCopyUsesUpdatedEnglishAndSimplifiedChineseStrings() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(english["library_city_title"], "City Cards")
        XCTAssertEqual(english["go_to_library"], "Go to City Cards")
        XCTAssertEqual(simplifiedChinese["library_city_title"], "城市卡")
        XCTAssertEqual(simplifiedChinese["go_to_library"], "去城市卡")
    }

    func test_friendProfileCopyUsesLocalizedStatsAndMenuTitles() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        let traditionalChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hant.lproj/Localizable.strings"))

        XCTAssertEqual(english["friend_profile_stat_trips"], "TRIPS")
        XCTAssertEqual(english["friend_profile_stat_memories"], "MEMORIES")
        XCTAssertEqual(english["friend_profile_stat_cities"], "CITIES")
        XCTAssertEqual(english["friend_city_cards_title"], "City Cards")
        XCTAssertEqual(english["journey_memory"], "Journey Memory")

        XCTAssertEqual(simplifiedChinese["friend_profile_stat_trips"], "旅程")
        XCTAssertEqual(simplifiedChinese["friend_profile_stat_memories"], "记忆")
        XCTAssertEqual(simplifiedChinese["friend_profile_stat_cities"], "城市卡片")
        XCTAssertEqual(simplifiedChinese["friend_city_cards_title"], "城市卡")
        XCTAssertEqual(simplifiedChinese["journey_memory"], "旅程记忆")

        XCTAssertEqual(traditionalChinese["friend_city_cards_title"], "城市卡")
    }
}
