import XCTest
@testable import StreetStamps

final class PostcardCityOptionsPresentationTests: XCTestCase {
    func test_buildOptions_returnsEnglishName() {
        let city = CachedCity(
            id: "Seoul|KR",
            name: "Seoul",
            canonicalNameEN: "Seoul",
            countryISO2: "KR",
            journeyIds: [],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            parentScopeKey: "Seoul Special City|KR",
            availableLevelNamesEN: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "Seoul",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "Seoul Special City"
            ],
            isTemporary: false
        )

        let options = PostcardCityOptionsPresentation.buildOptions(
            cachedCities: [city],
            journeyCandidates: []
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.id, "Seoul|KR")
    }
}
