import XCTest
@testable import StreetStamps

final class PostcardCityOptionsPresentationTests: XCTestCase {
    func test_buildOptions_prefersFreshResolvedNameOverStalePrefetchCache() {
        let city = CachedCity(
            id: "Seoul|KR",
            name: "Seoul",
            countryISO2: "KR",
            journeyIds: [],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: CityPlacemarkResolver.CardLevel.locality.rawValue,
            reservedParentRegionKey: "Seoul Special City|KR",
            reservedAvailableLevelNames: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "Seoul",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "Seoul Special City"
            ],
            isTemporary: false,
            reservedAvailableLevelNamesLocaleID: "en_US",
            localizedDisplayNameByLocale: ["en_US": "Seoul Special City"]
        )

        let options = PostcardCityOptionsPresentation.buildOptions(
            cachedCities: [city],
            journeyCandidates: [],
            localizedCityNamesByID: ["Seoul|KR": "首尔"],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.id, "Seoul|KR")
        XCTAssertEqual(options.first?.name, "Seoul Special City")
    }
}
