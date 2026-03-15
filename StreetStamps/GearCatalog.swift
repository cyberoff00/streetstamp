//
//  GearCatalog.swift
//  StreetStamps
//
//  Data-driven avatar equipment catalog (JSON in bundle).
//  This is meant to scale to a full "pixel character combination library".
//
//  Created by Claire Yang on 06/02/2026.
//

import Foundation
import SwiftUI

// MARK: - Catalog Models

struct AvatarCatalog: Codable, Equatable {
    var version: Int
    var base: BaseParts
    var categories: [GearCategory]

    struct BaseParts: Codable, Equatable {
        var body: PartImages
        var head: PartImages
        var baseOutfit: PartImages
    }
}

struct PartImages: Codable, Equatable {
    var front: String?
    var right: String?
    var back: String?
    var left: String?
}

struct GearCategory: Codable, Equatable, Identifiable {
    var id: String
    var titleKey: String
    /// Which property of RobotLoadout this category controls (hairId / suitId / upperId / underId / shoesId / hatId / glassId / accessoryId / expressionId).
    var selectionKey: String
    var items: [GearItem]
}

struct GearItem: Codable, Equatable, Identifiable {
    var id: String
    var nameKey: String
    var layer: String
    var images: PartImages
}

// MARK: - Loader / Access

final class AvatarCatalogStore: ObservableObject {
    static let shared = AvatarCatalogStore()

    @Published private(set) var catalog: AvatarCatalog = AvatarCatalogStore.fallbackCatalog()

    private init() {
        loadFromBundle()
    }

    func loadFromBundle() {
        guard let url = Bundle.main.url(forResource: "AvatarCatalog", withExtension: "json") else {
            // Keep fallback if missing.
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(AvatarCatalog.self, from: data)
            self.catalog = decoded
        } catch {
            // Keep fallback if decode fails.
            #if DEBUG
            print("AvatarCatalog decode failed:", error)
            #endif
        }
    }

    func item(categoryId: String, itemId: String) -> GearItem? {
        let normalizedItemId: String
        if categoryId == "hair" {
            normalizedItemId = RobotLoadout.normalizedHairId(itemId)
        } else {
            normalizedItemId = itemId
        }
        return catalog.categories.first(where: { $0.id == categoryId })?.items.first(where: { $0.id == normalizedItemId })
    }

    func imageName(_ images: PartImages, face: RobotFace) -> String? {
        switch face {
        case .front: return images.front
        case .right: return images.right
        case .back: return images.back
        case .left: return images.left
        }
    }

    // MARK: Fallback (keeps app usable even if JSON is missing)
    static func fallbackCatalog() -> AvatarCatalog {
        AvatarCatalog(
            version: 2,
            base: .init(
                body: .init(front: "front_body0001", right: nil, back: nil, left: nil),
                head: .init(front: "front_head0001", right: nil, back: nil, left: nil),
                baseOutfit: .init(front: "front_upper0001", right: nil, back: nil, left: nil)
            ),
            categories: [
                .init(
                    id: "expression",
                    titleKey: "equipment_expression",
                    selectionKey: "expressionId",
                    items: [
                        .init(
                            id: "expr_0001",
                            nameKey: "Expression 0001",
                            layer: "expression",
                            images: .init(front: "front_exp0001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "expr_0012",
                            nameKey: "Expression 0012",
                            layer: "expression",
                            images: .init(front: "front_exp012", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "expr_0013",
                            nameKey: "Expression 0013",
                            layer: "expression",
                            images: .init(front: "front_exp013", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "hair",
                    titleKey: "equipment_hair",
                    selectionKey: "hairId",
                    items: [
                        .init(
                            id: "hair_0001",
                            nameKey: "Hair 0001",
                            layer: "hair",
                            images: .init(front: "front_hair0001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0002",
                            nameKey: "Hair 0002",
                            layer: "hair",
                            images: .init(front: "front_hair0002", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0003",
                            nameKey: "Hair 0003",
                            layer: "hair",
                            images: .init(front: "front_hair001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0004",
                            nameKey: "Hair 0004",
                            layer: "hair",
                            images: .init(front: "front_hair002", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0005",
                            nameKey: "Hair 0005",
                            layer: "hair",
                            images: .init(front: "front_hair003", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0006",
                            nameKey: "Hair 0006",
                            layer: "hair",
                            images: .init(front: "front_hair004", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0007",
                            nameKey: "Hair 0007",
                            layer: "hair",
                            images: .init(front: "front_hair005", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0008",
                            nameKey: "Hair 0008",
                            layer: "hair",
                            images: .init(front: "front_hair006", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0010",
                            nameKey: "Hair 0010",
                            layer: "hair",
                            images: .init(front: "front_hair007", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0011",
                            nameKey: "Hair 0011",
                            layer: "hair",
                            images: .init(front: "front_hair008", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0012",
                            nameKey: "Hair 0012",
                            layer: "hair",
                            images: .init(front: "front_hair009", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0013",
                            nameKey: "Hair 0013",
                            layer: "hair",
                            images: .init(front: "front_hair010", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0014",
                            nameKey: "Hair 0014",
                            layer: "hair",
                            images: .init(front: "front_hair011", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hair_0015",
                            nameKey: "Hair 0015",
                            layer: "hair",
                            images: .init(front: "front_hair012", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "suit",
                    titleKey: "equipment_suit",
                    selectionKey: "suitId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "suit",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0001",
                            nameKey: "Suit 0001",
                            layer: "suit",
                            images: .init(front: "front_suit001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0002",
                            nameKey: "Suit 0002",
                            layer: "suit",
                            images: .init(front: "front_suit002", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0003",
                            nameKey: "Suit 0003",
                            layer: "suit",
                            images: .init(front: "front_suit003", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0004",
                            nameKey: "Suit 0004",
                            layer: "suit",
                            images: .init(front: "front_suit004", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0005",
                            nameKey: "Suit 0005",
                            layer: "suit",
                            images: .init(front: "front_suit005", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0006",
                            nameKey: "Suit 0006",
                            layer: "suit",
                            images: .init(front: "front_suit006", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0007",
                            nameKey: "Suit 0007",
                            layer: "suit",
                            images: .init(front: "front_suit007", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "suit_0008",
                            nameKey: "Suit 0008",
                            layer: "suit",
                            images: .init(front: "front_suit008", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "upper",
                    titleKey: "equipment_upper",
                    selectionKey: "upperId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "upper",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0001",
                            nameKey: "Upper 0001",
                            layer: "upper",
                            images: .init(front: "front_upper0001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0009",
                            nameKey: "Upper 0009",
                            layer: "upper",
                            images: .init(front: "front_upper8", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0010",
                            nameKey: "Upper 0010",
                            layer: "upper",
                            images: .init(front: "front_upper009", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0011",
                            nameKey: "Upper 0011",
                            layer: "upper",
                            images: .init(front: "front_upper010", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0012",
                            nameKey: "Upper 0012",
                            layer: "upper",
                            images: .init(front: "front_upper011", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0013",
                            nameKey: "Upper 0013",
                            layer: "upper",
                            images: .init(front: "front_upper012", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0014",
                            nameKey: "Upper 0014",
                            layer: "upper",
                            images: .init(front: "front_upper013", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0015",
                            nameKey: "Upper 0015",
                            layer: "upper",
                            images: .init(front: "front_upper014", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "upper_0016",
                            nameKey: "Upper 0016",
                            layer: "upper",
                            images: .init(front: "front_upper015", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "under",
                    titleKey: "equipment_under",
                    selectionKey: "underId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "under",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "under_0001",
                            nameKey: "Under 0001",
                            layer: "under",
                            images: .init(front: "front_under0001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "under_0007",
                            nameKey: "Under 0007",
                            layer: "under",
                            images: .init(front: "front_under006", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "shoes",
                    titleKey: "equipment_shoes",
                    selectionKey: "shoesId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "shoes",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "shoes_0001",
                            nameKey: "Shoes 0001",
                            layer: "shoes",
                            images: .init(front: "front_shoes001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "shoes_0002",
                            nameKey: "Shoes 0002",
                            layer: "shoes",
                            images: .init(front: "front_shoes002", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "hat",
                    titleKey: "equipment_hat",
                    selectionKey: "hatId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "hat",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hat_001",
                            nameKey: "Hat 001",
                            layer: "hat",
                            images: .init(front: "front_hat001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "hat_012",
                            nameKey: "Hat 012",
                            layer: "hat",
                            images: .init(front: "front_hat012", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "glass",
                    titleKey: "equipment_glass",
                    selectionKey: "glassId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "glass",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "glass_001",
                            nameKey: "Glass 001",
                            layer: "glass",
                            images: .init(front: "front_glass001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "glass_012",
                            nameKey: "Glass 012",
                            layer: "glass",
                            images: .init(front: "front_glass012", right: nil, back: nil, left: nil)
                        )
                    ]
                ),
                .init(
                    id: "accessory",
                    titleKey: "equipment_accessory",
                    selectionKey: "accessoryId",
                    items: [
                        .init(
                            id: "none",
                            nameKey: "equipment_item_none",
                            layer: "accessory",
                            images: .init(front: nil, right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_001",
                            nameKey: "Accessory 001",
                            layer: "accessory",
                            images: .init(front: "front_ac001", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_002",
                            nameKey: "Accessory 002",
                            layer: "accessory",
                            images: .init(front: "front_ac002", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_003",
                            nameKey: "Accessory 003",
                            layer: "accessory",
                            images: .init(front: "front_ac003", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_004",
                            nameKey: "Accessory 004",
                            layer: "accessory",
                            images: .init(front: "front_ac004", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_005",
                            nameKey: "Accessory 005",
                            layer: "accessory",
                            images: .init(front: "front_ac005", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_006",
                            nameKey: "Accessory 006",
                            layer: "accessory",
                            images: .init(front: "front_ac007", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "acc_007",
                            nameKey: "Accessory 007",
                            layer: "accessory",
                            images: .init(front: "front_ac008", right: nil, back: nil, left: nil)
                        )
                    ]
                )
            ]
        )
    }
}

// MARK: - Tiny helper for optional localized strings

extension String {
    var l10nOrSelf: String {
        let localized = NSLocalizedString(self, comment: "")
        return localized == self ? self : localized
    }
}
