//
//  CoinStoreService.swift
//  StreetStamps
//
//  StoreKit 2 service for purchasing coin packs.
//  Product IDs are defined in GearPricingConfig.coinPackages.
//

import Foundation
import StoreKit
import Combine
import RevenueCat

@MainActor
final class CoinStoreService: ObservableObject {
    static let shared = CoinStoreService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasFinishedInitialLoad = false
    @Published private(set) var errorMessage: String?

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load products from App Store

    func loadProducts() async {
        guard products.isEmpty else {
            hasFinishedInitialLoad = true
            return
        }
        isLoading = true
        errorMessage = nil

        let ids = GearPricingConfig.coinPackages.map(\.productID)
        do {
            let storeProducts = try await Product.products(for: Set(ids))
            // Sort by price ascending
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("CoinStoreService: failed to load products:", error)
            #endif
        }
        isLoading = false
        hasFinishedInitialLoad = true
    }

    // MARK: - Purchase

    struct PurchaseOutcome {
        let coins: Int
        /// StoreKit transaction ID — the natural dedupe key for the coin
        /// grant, so a retry after a lost response can't double-credit.
        let transactionID: String?
    }

    func purchase(_ product: Product) async -> PurchaseOutcome? {
        do {
            let storeProduct = StoreProduct(sk2Product: product)
            let result = try await Purchases.shared.purchase(product: storeProduct)
            if result.userCancelled { return nil }
            return PurchaseOutcome(
                coins: coinsForProduct(product.id),
                transactionID: result.transaction?.transactionIdentifier
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    func coinsForProduct(_ productID: String) -> Int {
        GearPricingConfig.coinPackages.first(where: { $0.productID == productID })?.coins ?? 0
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.revocationDate != nil {
                        await self?.handleCoinPackRefund(productID: transaction.productID)
                    }
                }
            }
        }
    }

    /// Roll back coins for a refunded coin pack. Coins are consumable, so the
    /// user may have already spent some — we deduct what we can and floor at
    /// zero. Equipment already bought with refunded coins is not reclaimed
    /// (consumable economy doesn't track per-coin provenance).
    @MainActor
    private func handleCoinPackRefund(productID: String) async {
        let coins = coinsForProduct(productID)
        guard coins > 0 else { return }
        // CoinService.spend refuses to push the balance negative server-side;
        // if user already burned the coins, refund still proceeds and balance
        // sits at zero. Matches the "consumable economy doesn't track per-coin
        // provenance" rule above.
        _ = await CoinService.shared.spend(coins, reason: "iap_refund:\(productID)")
    }
}
