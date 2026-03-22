import Foundation

struct EquipmentEconomy: Codable, Equatable {
    var coins: Int
    var ownedItemsByCategory: [String: [String]]

    static let startingCoins = 0

    static var empty: EquipmentEconomy {
        EquipmentEconomy(coins: startingCoins, ownedItemsByCategory: [:])
    }

    mutating func bootstrapIfNeeded(catalog: AvatarCatalog, loadout: RobotLoadout) {
        // Always ensure free items are granted (handles both fresh and existing users)
        for category in catalog.categories {
            let freeIDs = GearPricingConfig.freeItemIDs(for: category.id, items: category.items)
            for id in freeIDs {
                markOwned(categoryId: category.id, itemId: id)
            }
            if category.items.contains(where: { $0.id == "none" }) {
                markOwned(categoryId: category.id, itemId: "none")
            }
        }

        ensureCurrentLoadoutOwned(loadout: loadout)
    }

    mutating func ensureCurrentLoadoutOwned(loadout: RobotLoadout) {
        markOwned(categoryId: "hair", itemId: loadout.hairId)
        markOwned(categoryId: "suit", itemId: "none")
        markOwned(categoryId: "upper", itemId: "none")
        markOwned(categoryId: "under", itemId: "none")
        markOwned(categoryId: "shoes", itemId: "none")
        if let suitId = loadout.suitId {
            markOwned(categoryId: "suit", itemId: suitId)
        }
        markOwned(categoryId: "upper", itemId: loadout.upperId)
        markOwned(categoryId: "under", itemId: loadout.underId)
        if let shoesId = loadout.shoesId {
            markOwned(categoryId: "shoes", itemId: shoesId)
        }
        markOwned(categoryId: "expression", itemId: loadout.expressionId)
        markOwned(categoryId: "hat", itemId: "none")
        markOwned(categoryId: "glass", itemId: "none")
        markOwned(categoryId: "accessory", itemId: "none")
        if let hatId = loadout.hatId {
            markOwned(categoryId: "hat", itemId: hatId)
        }
        if let glassId = loadout.glassId {
            markOwned(categoryId: "glass", itemId: glassId)
        }

        for accessoryId in loadout.accessoryIds {
            markOwned(categoryId: "accessory", itemId: accessoryId)
        }
    }

    func owns(categoryId: String, itemId: String) -> Bool {
        if itemId == "none" { return true }
        guard let owned = ownedItemsByCategory[categoryId] else { return false }
        return owned.contains(itemId)
    }

    func isFreeItem(categoryId: String, itemId: String, catalog: AvatarCatalog) -> Bool {
        guard let category = catalog.categories.first(where: { $0.id == categoryId }) else { return false }
        return GearPricingConfig.isFree(categoryId: categoryId, itemId: itemId, items: category.items)
    }

    mutating func markOwned(categoryId: String, itemId: String) {
        var set = Set(ownedItemsByCategory[categoryId] ?? [])
        set.insert(itemId)
        ownedItemsByCategory[categoryId] = Array(set)
    }

    private func equippedItemId(selectionKey: String, loadout: RobotLoadout) -> String? {
        switch selectionKey {
        case "hairId":
            return loadout.hairId
        case "suitId":
            return loadout.suitId
        case "upperId":
            return loadout.upperId
        case "underId":
            return loadout.underId
        case "hatId":
            return loadout.hatId
        case "glassId":
            return loadout.glassId
        case "shoesId":
            return loadout.shoesId
        case "accessoryId":
            return loadout.accessoryIds.first
        case "expressionId":
            return loadout.expressionId
        default:
            return nil
        }
    }
}

enum EquipmentEconomyStore {
    private static let key = "equipment.economy.v1"

    static func load() -> EquipmentEconomy {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(EquipmentEconomy.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func save(_ economy: EquipmentEconomy) {
        guard let data = try? JSONEncoder().encode(economy) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
