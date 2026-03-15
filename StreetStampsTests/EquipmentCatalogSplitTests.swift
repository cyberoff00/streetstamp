import XCTest
@testable import StreetStamps

final class EquipmentCatalogSplitTests: XCTestCase {
    func test_robotLoadoutSeparatesHatGlassAndAccessorySelections() throws {
        let loadout = RobotLoadout(
            hairId: "hair_0004",
            suitId: nil,
            upperId: "upper_0003",
            underId: "under_0002",
            shoesId: "shoes_0001",
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
        XCTAssertEqual(decoded.shoesId, "shoes_0001")
    }

    func test_avatarCatalogSplitsHatGlassAccessoryAndShoesCategories() throws {
        let catalog = try loadCatalog()

        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "hat" && $0.selectionKey == "hatId" }))
        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "glass" && $0.selectionKey == "glassId" }))
        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "accessory" && $0.selectionKey == "accessoryId" }))
        XCTAssertNotNil(catalog.categories.first(where: { $0.id == "shoes" && $0.selectionKey == "shoesId" }))
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

    func test_avatarCatalogIncludesImportedFrontAssetsInMatchingCategories() throws {
        let catalog = try loadCatalog()

        let expressions = try XCTUnwrap(catalog.categories.first(where: { $0.id == "expression" }))
        let hair = try XCTUnwrap(catalog.categories.first(where: { $0.id == "hair" }))
        let suits = try XCTUnwrap(catalog.categories.first(where: { $0.id == "suit" }))
        let upper = try XCTUnwrap(catalog.categories.first(where: { $0.id == "upper" }))
        let under = try XCTUnwrap(catalog.categories.first(where: { $0.id == "under" }))
        let hats = try XCTUnwrap(catalog.categories.first(where: { $0.id == "hat" }))
        let glasses = try XCTUnwrap(catalog.categories.first(where: { $0.id == "glass" }))
        let accessories = try XCTUnwrap(catalog.categories.first(where: { $0.id == "accessory" }))
        let shoes = try XCTUnwrap(catalog.categories.first(where: { $0.id == "shoes" }))

        XCTAssertTrue(expressions.items.contains(where: { $0.images.front == "front_exp012" }))
        XCTAssertTrue(expressions.items.contains(where: { $0.images.front == "front_exp013" }))
        XCTAssertTrue(hair.items.contains(where: { $0.images.front == "front_hair009" }))
        XCTAssertTrue(hair.items.contains(where: { $0.images.front == "front_hair012" }))
        XCTAssertTrue(suits.items.contains(where: { $0.images.front == "front_suit008" }))
        XCTAssertTrue(suits.items.contains(where: { $0.images.front == "front_suit009" }))
        XCTAssertTrue(upper.items.contains(where: { $0.images.front == "front_upper015" }))
        XCTAssertTrue(upper.items.contains(where: { $0.images.front == "front_upper016" }))
        XCTAssertTrue(under.items.contains(where: { $0.images.front == "front_under006" }))
        XCTAssertTrue(under.items.contains(where: { $0.images.front == "front_under007" }))
        XCTAssertTrue(hats.items.contains(where: { $0.images.front == "front_hat012" }))
        XCTAssertTrue(glasses.items.contains(where: { $0.images.front == "front_glass012" }))
        XCTAssertTrue(accessories.items.contains(where: { $0.images.front == "front_ac007" }))
        XCTAssertTrue(accessories.items.contains(where: { $0.images.front == "front_ac008" }))
        XCTAssertTrue(accessories.items.contains(where: { $0.images.front == "front_ac009" }))
        XCTAssertTrue(shoes.items.contains(where: { $0.images.front == "front_shoes001" }))
        XCTAssertTrue(shoes.items.contains(where: { $0.images.front == "front_shoes002" }))
    }

    func test_avatarCatalogAppendsSixNewestEquipmentAssetsToMatchingCategories() throws {
        let catalog = try loadCatalog()

        let pats = try XCTUnwrap(catalog.categories.first(where: { $0.id == "pat" }))
        let suits = try XCTUnwrap(catalog.categories.first(where: { $0.id == "suit" }))
        let accessories = try XCTUnwrap(catalog.categories.first(where: { $0.id == "accessory" }))

        XCTAssertTrue(accessories.items.contains(where: { $0.id == "acc_011" && $0.images.front == "front_ac012" }))
        XCTAssertTrue(accessories.items.contains(where: { $0.id == "acc_012" && $0.images.front == "front_ac013" }))

        XCTAssertTrue(pats.items.contains(where: { $0.id == "pat_005" && $0.images.front == "front_pat005" }))
        XCTAssertTrue(pats.items.contains(where: { $0.id == "pat_006" && $0.images.front == "front_pat006" }))
        XCTAssertTrue(pats.items.contains(where: { $0.id == "pat_007" && $0.images.front == "front_pat007" }))

        XCTAssertTrue(suits.items.contains(where: { $0.id == "suit_0010" && $0.images.front == "front_suit010" }))
    }

    func test_fallbackCatalogKeepsNewestImportedEquipmentItems() throws {
        let catalog = AvatarCatalogStore.fallbackCatalog()

        let suits = try XCTUnwrap(catalog.categories.first(where: { $0.id == "suit" }))
        let upper = try XCTUnwrap(catalog.categories.first(where: { $0.id == "upper" }))
        let under = try XCTUnwrap(catalog.categories.first(where: { $0.id == "under" }))
        let pats = try XCTUnwrap(catalog.categories.first(where: { $0.id == "pat" }))
        let accessories = try XCTUnwrap(catalog.categories.first(where: { $0.id == "accessory" }))

        XCTAssertEqual(suits.items.last?.id, "suit_0010")
        XCTAssertEqual(suits.items.last?.images.front, "front_suit010")
        XCTAssertEqual(upper.items.last?.id, "upper_0017")
        XCTAssertEqual(upper.items.last?.images.front, "front_upper016")
        XCTAssertEqual(under.items.last?.id, "under_0008")
        XCTAssertEqual(under.items.last?.images.front, "front_under007")
        XCTAssertEqual(pats.items.last?.id, "pat_007")
        XCTAssertEqual(pats.items.last?.images.front, "front_pat007")
        XCTAssertEqual(accessories.items.last?.id, "acc_012")
        XCTAssertEqual(accessories.items.last?.images.front, "front_ac013")
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
