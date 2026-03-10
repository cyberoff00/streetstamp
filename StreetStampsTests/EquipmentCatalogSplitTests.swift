import XCTest
@testable import StreetStamps

final class EquipmentCatalogSplitTests: XCTestCase {
    func test_robotLoadoutSeparatesHatGlassAndAccessorySelections() throws {
        let loadout = RobotLoadout(
            hairId: "hair_0004",
            suitId: nil,
            upperId: "upper_0003",
            underId: "under_0002",
            savedUpperIdForSuit: "upper_0003",
            savedUnderIdForSuit: "under_0002",
            hatId: "hat_001",
            glassId: "glass_002",
            accessoryIds: ["acc_001", "acc_003"],
            expressionId: "expr_0005"
        )

        let decoded = try JSONDecoder().decode(RobotLoadout.self, from: JSONEncoder().encode(loadout))

        XCTAssertEqual(decoded.hatId, "hat_001")
        XCTAssertEqual(decoded.glassId, "glass_002")
        XCTAssertEqual(decoded.accessoryIds, ["acc_001", "acc_003"])
    }

    func test_avatarCatalogSplitsHatGlassAndAccessoryCategories() throws {
        let catalog = try loadCatalog()

        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "hat" && $0.selectionKey == "hatId" }))
        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "glass" && $0.selectionKey == "glassId" }))
        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "accessory" && $0.selectionKey == "accessoryId" }))
    }

    func test_avatarCatalogRenumberedFrontAssetsStartAt001PerAccessoryType() throws {
        let catalog = try loadCatalog()

        let hats = try XCTUnwrap(catalog.categories.first(where: { $0.id == "hat" }))
        let glasses = try XCTUnwrap(catalog.categories.first(where: { $0.id == "glass" }))
        let accessories = try XCTUnwrap(catalog.categories.first(where: { $0.id == "accessory" }))

        XCTAssertEqual(hats.items.dropFirst().first?.id, "hat_001")
        XCTAssertEqual(hats.items.dropFirst().first?.images.front, "front_hat001")

        XCTAssertEqual(glasses.items.dropFirst().first?.id, "glass_001")
        XCTAssertEqual(glasses.items.dropFirst().first?.images.front, "front_glass001")

        XCTAssertEqual(accessories.items.dropFirst().first?.id, "acc_001")
        XCTAssertEqual(accessories.items.dropFirst().first?.images.front, "front_ac001")
    }

    func test_equipmentCategoryIconsMapHatGlassAndAccessoryToDedicatedAssets() {
        XCTAssertEqual(EquipmentCategoryIconAssetResolver.assetName(for: "hat"), "equipment_icon_hat")
        XCTAssertEqual(EquipmentCategoryIconAssetResolver.assetName(for: "glass"), "equipment_icon_glass")
        XCTAssertEqual(EquipmentCategoryIconAssetResolver.assetName(for: "accessory"), "equipment_icon_accessory 1")
        XCTAssertNil(EquipmentCategoryIconAssetResolver.assetName(for: "unknown"))
    }

    private func loadCatalog() throws -> AvatarCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StreetStamps/AvatarCatalog.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AvatarCatalog.self, from: data)
    }
}
