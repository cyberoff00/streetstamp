//
//  MembershipGateView.swift
//  StreetStamps
//
//  Reusable paywall prompt shown when a free user hits a premium-only feature.
//  Usage: .sheet(isPresented: $showGate) { MembershipGateView(feature: .globeView) }
//

import SwiftUI
import StoreKit

// MARK: - Gated Feature Descriptor

enum MembershipGatedFeature: Identifiable {
    case journeyPhotos
    case friends
    case globeView
    case republishJourney
    case postcardLimit
    case coinBoost
    case iCloudSync
    case gpxExport
    case mapAppearance

    var id: String {
        switch self {
        case .journeyPhotos:    return "journeyPhotos"
        case .friends:          return "friends"
        case .globeView:        return "globeView"
        case .republishJourney: return "republishJourney"
        case .postcardLimit:    return "postcardLimit"
        case .coinBoost:        return "coinBoost"
        case .iCloudSync:       return "iCloudSync"
        case .gpxExport:        return "gpxExport"
        case .mapAppearance:    return "mapAppearance"
        }
    }

    var iconName: String {
        switch self {
        case .journeyPhotos:    return "photo.on.rectangle.angled"
        case .friends:          return "person.2.fill"
        case .globeView:        return "globe.americas.fill"
        case .republishJourney: return "arrow.triangle.2.circlepath"
        case .postcardLimit:    return "envelope.fill"
        case .coinBoost:        return "bitcoinsign.circle.fill"
        case .iCloudSync:       return "icloud.fill"
        case .gpxExport:        return "square.and.arrow.up.fill"
        case .mapAppearance:    return "paintpalette.fill"
        }
    }

    var titleKey: String {
        switch self {
        case .journeyPhotos:    return "membership_gate_photos_title"
        case .friends:          return "membership_gate_friends_title"
        case .globeView:        return "membership_gate_globe_title"
        case .republishJourney: return "membership_gate_republish_title"
        case .postcardLimit:    return "membership_gate_postcard_title"
        case .coinBoost:        return "membership_gate_coin_title"
        case .iCloudSync:       return "membership_gate_icloud_title"
        case .gpxExport:        return "membership_gate_gpx_title"
        case .mapAppearance:    return "membership_gate_map_title"
        }
    }

    var descriptionKey: String {
        switch self {
        case .journeyPhotos:    return "membership_gate_photos_desc"
        case .friends:          return "membership_gate_friends_desc"
        case .globeView:        return "membership_gate_globe_desc"
        case .republishJourney: return "membership_gate_republish_desc"
        case .postcardLimit:    return "membership_gate_postcard_desc"
        case .coinBoost:        return "membership_gate_coin_desc"
        case .iCloudSync:       return "membership_gate_icloud_desc"
        case .gpxExport:        return "membership_gate_gpx_desc"
        case .mapAppearance:    return "membership_gate_map_desc"
        }
    }
}

// MARK: - Gate View

struct MembershipGateView: View {
    let feature: MembershipGatedFeature
    @Environment(\.dismiss) private var dismiss
    @StateObject private var membership = MembershipStore.shared
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var productsLoadFinished = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 24) {
                    featureHero
                    benefitsList
                    pricingSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .task {
            await loadProducts()
        }
    }

    // MARK: - Hero

    private var featureHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FigmaTheme.primary.opacity(0.25), FigmaTheme.accent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: feature.iconName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
            }

            Text(L10n.t(feature.titleKey))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(FigmaTheme.text)
                .multilineTextAlignment(.center)

            Text(L10n.t(feature.descriptionKey))
                .font(.system(size: 15))
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 8)
    }

    // MARK: - Benefits List

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "photo.on.rectangle.angled", textKey: "membership_benefit_photos")
            benefitRow(icon: "person.2.fill", textKey: "membership_benefit_friends")
            benefitRow(icon: "globe.americas.fill", textKey: "membership_benefit_globe")
            benefitRow(icon: "icloud.fill", textKey: "membership_benefit_icloud")
            benefitRow(icon: "square.and.arrow.up.fill", textKey: "membership_benefit_gpx")
            benefitRow(icon: "envelope.fill", textKey: "membership_benefit_postcard")
            benefitRow(icon: "paintpalette.fill", textKey: "membership_benefit_map")
            benefitRow(icon: "bitcoinsign.circle.fill", textKey: "membership_benefit_coins")
        }
        .padding(18)
        .background(FigmaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private func benefitRow(icon: String, textKey: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.primary)
                .frame(width: 24)

            Text(L10n.t(textKey))
                .font(.system(size: 14))
                .foregroundColor(FigmaTheme.text)
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 12) {
            if !products.isEmpty {
                ForEach(products, id: \.id) { product in
                    Button {
                        Task { await purchaseProduct(product) }
                    } label: {
                        pricingButtonLabel(
                            name: product.displayName,
                            period: product.subscription.map { subscriptionPeriodText($0.subscriptionPeriod) },
                            price: product.displayPrice
                        )
                    }
                    .disabled(isPurchasing)
                    .opacity(isPurchasing ? 0.6 : 1.0)
                }
            } else if productsLoadFinished {
                Button {
                    Task { await purchaseByID(MembershipStore.subscriptionProductID) }
                } label: {
                    pricingButtonLabel(
                        name: L10n.t("membership_plan_monthly"),
                        period: L10n.t("membership_period_monthly"),
                        price: "$2.99"
                    )
                }
                .disabled(isPurchasing)
                .opacity(isPurchasing ? 0.6 : 1.0)

                Button {
                    Task { await purchaseByID(MembershipStore.yearlyProductID) }
                } label: {
                    pricingButtonLabel(
                        name: L10n.t("membership_plan_yearly"),
                        period: L10n.t("membership_period_yearly"),
                        price: "$19.99"
                    )
                }
                .disabled(isPurchasing)
                .opacity(isPurchasing ? 0.6 : 1.0)
            } else {
                ProgressView()
                    .padding(.vertical, 12)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { try? await AppStore.sync() }
            } label: {
                Text(L10n.t("membership_restore_purchases"))
                    .font(.system(size: 14))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.top, 4)
        }
    }

    private func pricingButtonLabel(name: String, period: String?, price: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if let period {
                    Text(period)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Spacer()
            Text(price)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(FigmaTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    private func loadProducts() async {
        let ids: Set<String> = [
            MembershipStore.subscriptionProductID,
            MembershipStore.yearlyProductID
        ]
        do {
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            errorMessage = error.localizedDescription
        }
        productsLoadFinished = true
    }

    private func purchaseByID(_ productID: String) async {
        isPurchasing = true
        errorMessage = nil
        if products.isEmpty {
            await loadProducts()
        }
        guard let product = products.first(where: { $0.id == productID }) else {
            errorMessage = L10n.t("membership_products_unavailable")
            isPurchasing = false
            return
        }
        await purchaseProduct(product)
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        do {
            let success = try await membership.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    private func subscriptionPeriodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .month: return period.value == 1 ? L10n.t("membership_period_monthly") : "\(period.value) months"
        case .year:  return period.value == 1 ? L10n.t("membership_period_yearly") : "\(period.value) years"
        default:     return ""
        }
    }
}
