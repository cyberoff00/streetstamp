//
//  GearPricingConfig.swift
//  StreetStamps
//
//  Central, data-driven pricing & free-item config for the equipment store.
//  To adjust prices or free items, edit ONLY this file.
//

import Foundation

enum GearPricingConfig {

    // MARK: - Per-category coin price

    static func price(for categoryId: String) -> Int {
        switch categoryId {
        case "expression": return 100
        case "hair":       return 100
        case "suit":       return 500
        case "upper":      return 200
        case "under":      return 200
        case "hat":        return 200
        case "glass":      return 200
        case "accessory":  return 200
        case "pat":        return 500
        case "shoes":      return 200
        default:           return 200
        }
    }

    // MARK: - Free items per category
    //
    // Returns the set of item IDs that are free (no coins needed).
    // "none" items are always implicitly free — no need to list them here.

    static func freeItemIDs(for categoryId: String, items: [GearItem]) -> Set<String> {
        let visibleItems = items.filter { $0.id != "none" }

        switch categoryId {
        case "expression":
            return firstN(6, of: visibleItems)
        case "hair":
            return firstN(9, of: visibleItems)
        case "suit":
            return firstN(3, of: visibleItems)
        case "upper":
            return firstN(12, of: visibleItems)
        case "under":
            return firstN(6, of: visibleItems)
        case "hat":
            return hatFreeItems(visibleItems)
        case "glass":
            return firstN(6, of: visibleItems)
        case "accessory":
            return firstN(6, of: visibleItems)
        case "pat":
            // No free pet items by default. Change here if needed.
            return []
        case "shoes":
            return firstN(visibleItems.count, of: visibleItems) // all free for now
        default:
            return []
        }
    }

    static func isFree(categoryId: String, itemId: String, items: [GearItem]) -> Bool {
        if itemId == "none" { return true }
        return freeItemIDs(for: categoryId, items: items).contains(itemId)
    }

    // MARK: - IAP Coin Packages
    //
    // product ID -> coin amount. Register these in App Store Connect.

    struct CoinPackage {
        let productID: String
        let coins: Int
        let label: String // for display before StoreKit loads real price
    }

    static let coinPackages: [CoinPackage] = [
        CoinPackage(productID: "com.streetstamps.coins.1000", coins: 1000, label: "1000"),
        CoinPackage(productID: "com.streetstamps.coins.2500", coins: 2500, label: "2500"),
        CoinPackage(productID: "com.streetstamps.coins.5000", coins: 5000, label: "5000"),
    ]

    // MARK: - Helpers

    private static func firstN(_ n: Int, of items: [GearItem]) -> Set<String> {
        Set(items.prefix(n).map(\.id))
    }

    private static func hatFreeItems(_ visibleItems: [GearItem]) -> Set<String> {
        // All hats free EXCEPT the 2nd and the last (0-indexed: index 1 and last).
        guard visibleItems.count >= 2 else { return Set(visibleItems.map(\.id)) }
        var freeSet = Set(visibleItems.map(\.id))
        freeSet.remove(visibleItems[1].id)           // 2nd item
        freeSet.remove(visibleItems[visibleItems.count - 1].id)  // last item
        return freeSet
    }
}
