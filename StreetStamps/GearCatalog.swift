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
    /// Which property of RobotLoadout this category controls (hairId / suitId / upperId / underId / accessoryId / expressionId).
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
                            id: "acc_0001",
                            nameKey: "Accessory 0001",
                            layer: "accessory",
                            images: .init(front: "front_ac001", right: nil, back: nil, left: nil)
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
