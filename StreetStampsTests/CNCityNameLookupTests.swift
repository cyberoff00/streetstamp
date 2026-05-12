import XCTest
@testable import StreetStamps

final class CNCityNameLookupTests: XCTestCase {

    private let lookup = CNCityNameLookup.shared

    func test_municipalities_resolveWhenProvinceEqualsCity() {
        XCTAssertEqual(lookup.zhName(enCity: "Beijing", province: "Beijing", iso2: "CN"), "北京市")
        XCTAssertEqual(lookup.zhName(enCity: "Shanghai", province: "Shanghai", iso2: "CN"), "上海市")
        XCTAssertEqual(lookup.zhName(enCity: "Tianjin", province: "Tianjin", iso2: "CN"), "天津市")
        XCTAssertEqual(lookup.zhName(enCity: "Chongqing", province: "Chongqing", iso2: "CN"), "重庆市")
    }

    func test_userScreenshotCities_allResolve() {
        XCTAssertEqual(lookup.zhName(enCity: "Hohhot", province: "Inner Mongolia", iso2: "CN"), "呼和浩特市")
        XCTAssertEqual(lookup.zhName(enCity: "Huizhou", province: "Guangdong", iso2: "CN"), "惠州市")
        XCTAssertEqual(lookup.zhName(enCity: "Xi'an", province: "Shaanxi", iso2: "CN"), "西安市")
        XCTAssertEqual(lookup.zhName(enCity: "Aba", province: "Sichuan", iso2: "CN"), "阿坝藏族羌族自治州")
        XCTAssertEqual(lookup.zhName(enCity: "Alxa", province: "Inner Mongolia", iso2: "CN"), "阿拉善盟")
        XCTAssertEqual(lookup.zhName(enCity: "Baotou", province: "Inner Mongolia", iso2: "CN"), "包头市")
    }

    func test_provinceWithFormalSuffix_normalizes() {
        XCTAssertEqual(lookup.zhName(enCity: "Hohhot", province: "Inner Mongolia Autonomous Region", iso2: "CN"), "呼和浩特市")
        XCTAssertEqual(lookup.zhName(enCity: "Urumqi", province: "Xinjiang Uyghur Autonomous Region", iso2: "CN"), "乌鲁木齐市")
        XCTAssertEqual(lookup.zhName(enCity: "Lhasa", province: "Tibet Autonomous Region", iso2: "CN"), "拉萨市")
        XCTAssertEqual(lookup.zhName(enCity: "Nanning", province: "Guangxi Zhuang Autonomous Region", iso2: "CN"), "南宁市")
        XCTAssertEqual(lookup.zhName(enCity: "Yinchuan", province: "Ningxia Hui Autonomous Region", iso2: "CN"), "银川市")
    }

    func test_specialRomanizations() {
        XCTAssertEqual(lookup.zhName(enCity: "Harbin", province: "Heilongjiang", iso2: "CN"), "哈尔滨市")
        XCTAssertEqual(lookup.zhName(enCity: "Urumqi", province: "Xinjiang", iso2: "CN"), "乌鲁木齐市")
        XCTAssertEqual(lookup.zhName(enCity: "Lhasa", province: "Tibet", iso2: "CN"), "拉萨市")
        XCTAssertEqual(lookup.zhName(enCity: "Xiamen", province: "Fujian", iso2: "CN"), "厦门市")
    }

    func test_pinyinVariants_viaAliases() {
        XCTAssertEqual(lookup.zhName(enCity: "Xian", province: "Shaanxi", iso2: "CN"), "西安市")
        XCTAssertEqual(lookup.zhName(enCity: "Xi An", province: "Shaanxi", iso2: "CN"), "西安市")
        XCTAssertEqual(lookup.zhName(enCity: "Sian", province: "Shaanxi", iso2: "CN"), "西安市")
    }

    func test_historicalAliases() {
        XCTAssertEqual(lookup.zhName(enCity: "Canton", province: "Guangdong", iso2: "CN"), "广州市")
        XCTAssertEqual(lookup.zhName(enCity: "Tsingtao", province: "Shandong", iso2: "CN"), "青岛市")
        XCTAssertEqual(lookup.zhName(enCity: "Amoy", province: "Fujian", iso2: "CN"), "厦门市")
        XCTAssertEqual(lookup.zhName(enCity: "Mukden", province: "Liaoning", iso2: "CN"), "沈阳市")
    }

    func test_apostropheAndSpaceVariants() {
        XCTAssertEqual(lookup.zhName(enCity: "Xi'an", province: "Shaanxi", iso2: "CN"), "西安市")
        XCTAssertEqual(lookup.zhName(enCity: "Xi\u{2019}an", province: "Shaanxi", iso2: "CN"), "西安市")
    }

    func test_specialRegions_resolveWithoutProvince() {
        XCTAssertEqual(lookup.zhName(enCity: "Hong Kong", province: nil, iso2: "HK"), "香港特别行政区")
        XCTAssertEqual(lookup.zhName(enCity: "Macau", province: nil, iso2: "MO"), "澳门特别行政区")
        XCTAssertEqual(lookup.zhName(enCity: "Singapore", province: nil, iso2: "SG"), "新加坡")
        XCTAssertEqual(lookup.zhName(enCity: "Taiwan", province: nil, iso2: "TW"), "台湾")
    }

    func test_specialRegions_resolveWithProvinceFilledIn() {
        XCTAssertEqual(lookup.zhName(enCity: "Hong Kong", province: "Hong Kong", iso2: "HK"), "香港特别行政区")
        XCTAssertEqual(lookup.zhName(enCity: "Macao", province: nil, iso2: "MO"), "澳门特别行政区")
    }

    func test_provinceMismatch_returnsNil() {
        XCTAssertNil(lookup.zhName(enCity: "Hohhot", province: "Beijing", iso2: "CN"))
        XCTAssertNil(lookup.zhName(enCity: "Hangzhou", province: "Sichuan", iso2: "CN"))
    }

    func test_shaanxiVsShanxi_doNotCollide() {
        XCTAssertEqual(lookup.zhName(enCity: "Xi'an", province: "Shaanxi", iso2: "CN"), "西安市")
        XCTAssertEqual(lookup.zhName(enCity: "Taiyuan", province: "Shanxi", iso2: "CN"), "太原市")
        XCTAssertNil(lookup.zhName(enCity: "Xi'an", province: "Shanxi", iso2: "CN"))
        XCTAssertNil(lookup.zhName(enCity: "Taiyuan", province: "Shaanxi", iso2: "CN"))
    }

    func test_nonChineseCity_returnsNil() {
        XCTAssertNil(lookup.zhName(enCity: "Tokyo", province: "Tokyo", iso2: "JP"))
        XCTAssertNil(lookup.zhName(enCity: "Paris", province: "Île-de-France", iso2: "FR"))
        XCTAssertNil(lookup.zhName(enCity: "New York", province: "New York", iso2: "US"))
    }

    func test_unknownCnCity_returnsNil() {
        XCTAssertNil(lookup.zhName(enCity: "ZZTopVille", province: "Guangdong", iso2: "CN"))
    }

    func test_normalizeStripsAdminSuffixes() {
        XCTAssertEqual(CNCityNameLookup.normalize("Beijing Shi"), "beijing")
        XCTAssertEqual(CNCityNameLookup.normalize("Inner Mongolia Autonomous Region"), "innermongolia")
        XCTAssertEqual(CNCityNameLookup.normalize("Xinjiang Uyghur Autonomous Region"), "xinjiang")
        XCTAssertEqual(CNCityNameLookup.normalize("Xi'an"), "xian")
        XCTAssertEqual(CNCityNameLookup.normalize("Xi\u{2019}an"), "xian")
    }
}
