//
//  CoinStoreService.swift
//  StreetStamps
//
//  StoreKit 2 service for purchasing coin packs.
//  Product IDs are defined in GearPricingConfig.coinPackages.
//

import Foundation
import StoreKit

@MainActor
final class CoinStoreService: ObservableObject {
    static let shared = CoinStoreService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
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
        guard products.isEmpty else { return }
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
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Int? {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let coins = coinsForProduct(transaction.productID)
                await transaction.finish()
                return coins
            case .userCancelled:
                return nil
            case .pending:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    func coinsForProduct(_ productID: String) -> Int {
        GearPricingConfig.coinPackages.first(where: { $0.productID == productID })?.coins ?? 0
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }
}
