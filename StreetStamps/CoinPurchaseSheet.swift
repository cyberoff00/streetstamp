//
//  CoinPurchaseSheet.swift
//  StreetStamps
//
//  Sheet UI for purchasing coin packs via IAP.
//

import SwiftUI
import StoreKit

enum CoinPurchaseSheetContentState: Equatable {
    case loading
    case fallback
    case products

    static func resolve(
        hasFinishedInitialLoad: Bool,
        isLoading: Bool,
        productsCount: Int
    ) -> CoinPurchaseSheetContentState {
        if isLoading || (!hasFinishedInitialLoad && productsCount == 0) {
            return .loading
        }

        if productsCount == 0 {
            return .fallback
        }

        return .products
    }
}

struct CoinPurchaseSheet: View {
    @Binding var economy: EquipmentEconomy
    var onDismiss: () -> Void

    @StateObject private var store = CoinStoreService.shared
    @ObservedObject private var membership = MembershipStore.shared
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                header
                currentBalanceHeader
                if !membership.isPremium {
                    premiumBanner
                }
                content

                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
            .padding(.top, 16)
            .background(FigmaTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .task {
            await store.loadProducts()
        }
    }

    private var contentState: CoinPurchaseSheetContentState {
        CoinPurchaseSheetContentState.resolve(
            hasFinishedInitialLoad: store.hasFinishedInitialLoad,
            isLoading: store.isLoading,
            productsCount: store.products.count
        )
    }

    @ViewBuilder
    private var content: some View {
        switch contentState {
        case .loading:
            ProgressView()
                .padding(.top, 40)
        case .fallback:
            fallbackPackageList
        case .products:
            storeKitProductList
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 44, height: 44)

            Spacer()

            Text(L10n.t("buy_coins"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(FigmaTheme.text)

            Spacer()

            AppCloseButton(style: .circleSubtle, action: onDismiss)
        }
        .padding(.horizontal, 20)
    }

    private var currentBalanceHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(FigmaTheme.primary)

            Text("\(economy.coins)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(FigmaTheme.text)

            Text(L10n.t("equipment_coins_label"))
                .font(.system(size: 15))
                .foregroundColor(FigmaTheme.subtext)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Premium upsell banner

    private var premiumBanner: some View {
        NavigationLink {
            MembershipSubscriptionView()
                .environmentObject(MembershipStore.shared)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("coin_sheet_premium_title"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(L10n.t("coin_sheet_premium_subtitle"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.10), FigmaTheme.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - StoreKit product list (real IAP)

    private var storeKitProductList: some View {
        VStack(spacing: 12) {
            ForEach(store.products, id: \.id) { product in
                let coins = store.coinsForProduct(product.id)
                Button {
                    Task { await purchaseProduct(product, coins: coins) }
                } label: {
                    coinPackageRow(
                        coins: coins,
                        priceLabel: product.displayPrice
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Fallback (before products load or in sandbox)

    private var fallbackPackageList: some View {
        VStack(spacing: 12) {
            ForEach(GearPricingConfig.coinPackages, id: \.productID) { pkg in
                coinPackageRow(
                    coins: pkg.coins,
                    priceLabel: fallbackPrice(for: pkg)
                )
                .opacity(0.6)
            }

            Text(L10n.t("equipment_iap_loading_hint"))
                .font(.system(size: 12))
                .foregroundColor(FigmaTheme.subtext)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func coinPackageRow(coins: Int, priceLabel: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.primary)

                Text("\(coins)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text(L10n.t("equipment_coins_label"))
                    .font(.system(size: 14))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Spacer()

            Text(priceLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FigmaTheme.primary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private func purchaseProduct(_ product: Product, coins: Int) async {
        isPurchasing = true
        if let earnedCoins = await store.purchase(product) {
            economy.coins += earnedCoins
            EquipmentEconomyStore.save(economy)
            onDismiss()
        }
        isPurchasing = false
    }

    private func fallbackPrice(for pkg: GearPricingConfig.CoinPackage) -> String {
        // Rough USD estimate: 500 coins = $0.49
        let usd = Double(pkg.coins) / 500.0 * 0.49
        return String(format: "$%.2f", usd)
    }
}
