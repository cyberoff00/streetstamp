//
//  MembershipGateView.swift
//  StreetStamps
//
//  Unified subscription paywall.
//  Shows a polished, single-design gate regardless of which feature triggered it.
//  Usage: .sheet(isPresented: $showGate) { MembershipGateView() }
//

import SwiftUI
import StoreKit

// MARK: - Gated Feature Descriptor (kept for call-site compatibility)

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
    case photoCityDiscovery

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
        case .photoCityDiscovery: return "photoCityDiscovery"
        }
    }
}

// MARK: - Unified Gate View

struct MembershipGateView: View {
    /// Optional — kept for backward compatibility. The gate always shows the
    /// same unified design regardless of which feature triggered it.
    var feature: MembershipGatedFeature? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var membership = MembershipStore.shared
    @ObservedObject private var featureFlags = FeatureFlagStore.shared
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var productsLoadFinished = false
    @State private var selectedProductID: String?

    private var sortedProducts: [Product] {
        products.sorted { $0.price < $1.price }
    }


    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    benefitsGrid
                        .padding(.top, 28)
                    planCards
                        .padding(.top, 24)
                    subscribeButton
                        .padding(.top, 20)
                    footer
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .task {
            await loadProducts()
            if selectedProductID == nil, let first = sortedProducts.first {
                selectedProductID = first.id
            }
        }
        .alert(
            L10n.t("membership_welcome_bonus_title"),
            isPresented: $membership.showWelcomeBonusAlert
        ) {
            Button(L10n.t("membership_welcome_bonus_ok"), role: .cancel) { dismiss() }
        } message: {
            Text(String(format: L10n.t("membership_welcome_bonus_message"), MembershipTierConfig.premiumWelcomeBonus))
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FigmaTheme.primary.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
            }
            .padding(.top, 16)

            Text(L10n.t("membership_gate_title"))
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(FigmaTheme.text)
                .multilineTextAlignment(.center)

            Text(L10n.t("membership_gate_subtitle"))
                .font(.system(size: 15))
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Benefits Grid (2 columns)

    private var benefitsGrid: some View {
        // Social-gated entries (photos-per-journey / friends / postcard) are
        // hidden in restricted storefront regions (e.g. mainland China).
        let socialEnabled = featureFlags.socialEnabled
        var items: [(icon: String, key: String)] = []
        items.append(("globe.americas.fill", "membership_benefit_globe"))
        if socialEnabled {
            items.append(("photo.on.rectangle.angled", "membership_benefit_photos"))
            items.append(("person.2.fill", "membership_benefit_friends"))
            items.append(("envelope.fill", "membership_benefit_postcard"))
        }
        items.append(("icloud.fill", "membership_benefit_icloud"))
        items.append(("paintpalette.fill", "membership_benefit_map"))
        items.append(("square.and.arrow.up.fill", "membership_benefit_gpx"))
        items.append(("bag.fill", "membership_benefit_equipment_coins"))

        return VStack(spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 10
            ) {
                ForEach(items, id: \.key) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(FigmaTheme.primary)
                            .frame(width: 18, height: 18)
                            .background(FigmaTheme.primary.opacity(0.12))
                            .clipShape(Circle())

                        Text(L10n.t(item.key))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(FigmaTheme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(FigmaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FigmaTheme.border, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(FigmaTheme.primary.opacity(0.7))
                Text(L10n.t("membership_benefit_more_features"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 10) {
            if !products.isEmpty {
                ForEach(sortedProducts, id: \.id) { product in
                    planCard(
                        id: product.id,
                        name: product.displayName,
                        period: product.subscription.map { periodText($0.subscriptionPeriod) },
                        price: product.displayPrice,
                        isYearly: product.id == MembershipStore.yearlyProductID
                    )
                }
            } else if productsLoadFinished {
                planCard(
                    id: MembershipStore.subscriptionProductID,
                    name: L10n.t("membership_plan_monthly"),
                    period: L10n.t("membership_period_monthly"),
                    price: "$2.99",
                    isYearly: false
                )
                planCard(
                    id: MembershipStore.yearlyProductID,
                    name: L10n.t("membership_plan_yearly"),
                    period: L10n.t("membership_period_yearly"),
                    price: "$19.99",
                    isYearly: true
                )
            } else {
                ProgressView()
                    .tint(FigmaTheme.primary)
                    .padding(.vertical, 16)
            }
        }
    }

    private func planCard(id: String, name: String, period: String?, price: String, isYearly: Bool) -> some View {
        let selected = selectedProductID == id

        return Button {
            selectedProductID = id
        } label: {
            HStack(spacing: 14) {
                // Radio dot
                ZStack {
                    Circle()
                        .stroke(selected ? FigmaTheme.primary : Color.black.opacity(0.15), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle()
                            .fill(FigmaTheme.primary)
                            .frame(width: 11, height: 11)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)

                        if isYearly {
                            Text(L10n.t("membership_save_badge"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FigmaTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    if let period {
                        Text(period)
                            .font(.system(size: 11))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                Spacer()

                Text(price)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(selected ? FigmaTheme.primary : FigmaTheme.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? FigmaTheme.primary : FigmaTheme.border,
                            lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await performPurchase() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.t("membership_subscribe_button"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    if !isPurchasing {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(FigmaTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isPurchasing || selectedProductID == nil)
            .opacity(isPurchasing ? 0.7 : 1.0)
            .buttonStyle(.plain)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    try? await AppStore.sync()
                    await membership.refreshEntitlement()
                }
            } label: {
                Text(L10n.t("membership_restore_purchases"))
                    .font(.system(size: 13))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Text(L10n.t("membership_auto_renew_note"))
                .font(.system(size: 10))
                .foregroundColor(FigmaTheme.subtext.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
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
            if selectedProductID == nil, let first = sortedProducts.first {
                selectedProductID = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        productsLoadFinished = true
        if selectedProductID == nil {
            selectedProductID = MembershipStore.subscriptionProductID
        }
    }

    private func performPurchase() async {
        guard let productID = selectedProductID else { return }
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
        do {
            let success = try await membership.purchase(product)
            if success {
                // Don't dismiss here — let the welcome bonus alert show first.
                // The view will dismiss when the user closes the alert.
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .month: return period.value == 1 ? L10n.t("membership_period_monthly") : "\(period.value) months"
        case .year:  return period.value == 1 ? L10n.t("membership_period_yearly") : "\(period.value) years"
        default:     return ""
        }
    }
}
