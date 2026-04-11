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
          "identityLevelRaw": "locality",
          "reservedParentRegionKey": "Shenzhen|CN",
          "reservedAvailableLevelNames": {
            "locality": "Nanshan District",
            "subAdmin": "Shenzhen",
            "admin": "Guangdong"
          },
          "reservedAvailableLevelNamesLocaleID": "en",
          "isTemporary": false
        }
        """.data(using: .utf8)!

        let city = try JSONDecoder().decode(CachedCity.self, from: json)

        XCTAssertEqual(city.id, "Nanshan District|CN")
        XCTAssertEqual(city.cityKey, "Nanshan District|CN")
        XCTAssertEqual(city.canonicalNameEN, "Nanshan District")
        XCTAssertEqual(city.parentScopeKey, "Shenzhen|CN")
        XCTAssertEqual(city.availableLevelNamesEN?["subAdmin"], "Shenzhen")
        XCTAssertEqual(city.availableLevelNamesEN?["locality"], "Nanshan District")
        XCTAssertEqual(city.availableLevelNamesEN?["admin"], "Guangdong")
        XCTAssertEqual(city.displayTitle, "Nanshan District")
        XCTAssertEqual(city.identityLevel, .locality)
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
            thumbnailRoutePath: nil,
            identityLevelRaw: "subAdmin"
        )

        XCTAssertEqual(city.cityKey, "Shenzhen|CN")
        XCTAssertEqual(city.canonicalNameEN, "Shenzhen")
        XCTAssertEqual(city.displayTitle, "Shenzhen")
        XCTAssertEqual(city.identityLevel, .subAdmin)
        XCTAssertNil(city.parentScopeKey)
        XCTAssertNil(city.availableLevelNamesEN)
    }
}
