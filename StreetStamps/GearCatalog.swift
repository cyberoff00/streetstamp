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
    /// Which property of RobotLoadout this category controls (hairId / outfitId / accessoryId).
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
        catalog.categories.first(where: { $0.id == categoryId })?.items.first(where: { $0.id == itemId })
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
            version: 1,
            base: .init(
                body: .init(front: "avatar_body_front", right: "avatar_body_side", back: nil, left: "avatar_body_side"),
                head: .init(front: "avatar_head_front", right: "avatar_head_side", back: nil, left: "avatar_head_side"),
                baseOutfit: .init(front: "avatar_base_top_front", right: "avatar_base_top_side", back: nil, left: "avatar_base_top_side")
            ),
            categories: [
                .init(
                    id: "hair",
                    titleKey: "equipment_hair",
                    selectionKey: "hairId",
                    items: [
                        .init(
                            id: "hair_boy_default",
                            nameKey: "equipment_item_hair_boy",
                            layer: "hair",
                            images: .init(front: "avatar_hair_boy_front", right: "avatar_hair_boy_side", back: nil, left: "avatar_hair_boy_side")
                        ),
                        .init(
                            id: "hair_girl_default",
                            nameKey: "equipment_item_hair_girl",
                            layer: "hair",
                            images: .init(front: "avatar_hair_girl_front", right: "avatar_hair_girl_side", back: nil, left: "avatar_hair_girl_side")
                        )
                    ]
                ),
                .init(
                    id: "outfit",
                    titleKey: "equipment_outfit",
                    selectionKey: "outfitId",
                    items: [
                        .init(
                            id: "outfit_boy_suit",
                            nameKey: "equipment_item_outfit_boy_suit",
                            layer: "outfit",
                            images: .init(front: "avatar_outfit_boy_suit_front", right: nil, back: nil, left: nil)
                        ),
                        .init(
                            id: "outfit_girl_suit",
                            nameKey: "equipment_item_outfit_girl_suit",
                            layer: "outfit",
                            images: .init(front: "avatar_outfit_girl_suit_front", right: nil, back: nil, left: nil)
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
                            id: "acc_headphone",
                            nameKey: "equipment_item_acc_headphone",
                            layer: "accessory",
                            images: .init(front: "avatar_acc_headphone_front", right: "avatar_acc_headphone_side", back: nil, left: "avatar_acc_headphone_side")
                        )
                    ]
                ),
                .init(
                    id: "expression",
                    titleKey: "equipment_expression",
                    selectionKey: "expressionId",
                    items: [
                        .init(
                            id: "expr_default",
                            nameKey: "equipment_item_expr_default",
                            layer: "expression",
                            images: .init(front: "avatar_expr_default_front", right: "avatar_expr_default_side", back: nil, left: "avatar_expr_default_side")
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
