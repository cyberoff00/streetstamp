import XCTest
@testable import StreetStamps

final class CachedCityModelTests: XCTestCase {
    func test_legacyCachedCityDecodesIntoNewModelFields() throws {
        let json = """
        {
          "id": "Nanshan District|CN",
          "name": "Nanshan District",
          "countryISO2": "CN",
          "journeyIds": ["journey-1"],
          "explorations": 1,
          "memories": 2,
          "reservedLevelRaw": "subAdmin",
          "reservedParentRegionKey": "Shenzhen|CN",
          "reservedAvailableLevelNames": {
            "locality": "Nanshan District",
            "subAdmin": "Shenzhen",
            "admin": "Guangdong"
          },
          "reservedAvailableLevelNamesLocaleID": "en",
          "localizedDisplayNameByLocale": {
            "en": "Shenzhen"
          },
          "isTemporary": false
        }
        """.data(using: .utf8)!

        let city = try JSONDecoder().decode(CachedCity.self, from: json)

        XCTAssertEqual(city.id, "Nanshan District|CN")
        XCTAssertEqual(city.cityKey, "Nanshan District|CN")
        XCTAssertEqual(city.canonicalNameEN, "Nanshan District")
        XCTAssertEqual(city.selectedDisplayLevelRaw, "subAdmin")
        XCTAssertEqual(city.parentScopeKey, "Shenzhen|CN")
        XCTAssertEqual(city.availableLevelNames?["subAdmin"], "Shenzhen")
        XCTAssertEqual(city.availableLevelNamesLocaleID, "en")
        XCTAssertEqual(city.reservedLevelRaw, "subAdmin")
        XCTAssertEqual(city.reservedParentRegionKey, "Shenzhen|CN")
    }

    func test_cachedCityInitializerDefaultsIdentityFieldsFromExistingArguments() {
        let city = CachedCity(
            id: "Shenzhen|CN",
            name: "Shenzhen",
            countryISO2: "CN",
            journeyIds: ["journey-1"],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil
        )

        XCTAssertEqual(city.cityKey, "Shenzhen|CN")
        XCTAssertEqual(city.canonicalNameEN, "Shenzhen")
        XCTAssertNil(city.identityLevelRaw)
        XCTAssertNil(city.selectedDisplayLevelRaw)
    }
}
