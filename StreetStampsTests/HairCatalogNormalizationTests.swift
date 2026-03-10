import XCTest
@testable import StreetStamps

final class HairCatalogNormalizationTests: XCTestCase {
    func test_hair0007RemainsDistinct() {
        let loadout = RobotLoadout(hairId: "hair_0007")

        XCTAssertEqual(loadout.hairId, "hair_0007")
    }
}
