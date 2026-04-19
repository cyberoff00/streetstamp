//
//  MembershipSubscriptionView.swift
//  StreetStamps
//
//  Full-page subscription management view.
//  Accessible from Settings > Subscription.
//  Shows current membership status, benefits comparison, plan selection, and purchase.
//

import SwiftUI
import StoreKit

struct MembershipSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var membership: MembershipStore
    @ObservedObject private var featureFlags = FeatureFlagStore.shared
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var selectedProductID: String?
    @State private var productsLoadFinished = false
    @State private var activeInfoKey: String?

    private var sortedProducts: [Product] {
        products.sorted { $0.price < $1.price }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                if membership.isPremium {
                    activeBenefitsCard
                        .padding(.bottom, 24)
                } else {
                    planSelector
                    compareFeaturesHeading
                    comparisonTable
                }
                restoreAndTerms
                indieNote
            }
            .padding(.bottom, membership.isPremium ? 40 : 110)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .onTapGesture {
            if activeInfoKey != nil {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { activeInfoKey = nil }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                AppBackButton()
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FigmaTheme.mutedBackground)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !membership.isPremium {
                stickyPurchaseBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
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
            Button(L10n.t("membership_welcome_bonus_ok"), role: .cancel) {}
        } message: {
            Text(String(format: L10n.t("membership_welcome_bonus_message"), MembershipTierConfig.premiumWelcomeBonus))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(membership.isPremium
                          ? FigmaTheme.secondary.opacity(0.15)
                          : FigmaTheme.primary.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(membership.isPremium ? FigmaTheme.secondary : FigmaTheme.primary)
            }
            .padding(.top, 28)

            Text(membership.isPremium
                 ? L10n.t("membership_status_active")
                 : L10n.t("membership_hero_title"))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(FigmaTheme.text)
                .multilineTextAlignment(.center)

            if !membership.isPremium {
                Text(L10n.t("membership_upgrade_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(FigmaTheme.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Compare Features Heading

    private var compareFeaturesHeading: some View {
        Text(L10n.t("membership_compare_features_title"))
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(FigmaTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 12)
    }

    // MARK: - Sticky Purchase Bar

    private var stickyPurchaseBar: some View {
        VStack(spacing: 4) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            Button {
                Task { await performPurchase() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(stickyButtonLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    if !isPurchasing {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(FigmaTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isPurchasing || selectedProductID == nil)
            .opacity(isPurchasing ? 0.7 : 1.0)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(
            FigmaTheme.mutedBackground
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
        )
    }

    private var stickyButtonLabel: String {
        guard let id = selectedProductID else {
            return L10n.t("membership_subscribe_button")
        }
        if id == MembershipStore.yearlyProductID {
            return L10n.t("membership_cta_yearly")
        }
        return L10n.t("membership_cta_monthly")
    }

    // MARK: - Indie Note

    private var indieNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundColor(FigmaTheme.primary.opacity(0.6))
                .padding(.top, 1)
            Text(L10n.t("membership_indie_note"))
                .font(.system(size: 12))
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Active Benefits Card (premium users)

    private struct BenefitRow {
        let icon: String
        let key: String
    }

    // Social-gated entries are filtered out in restricted storefront regions
    // (e.g. mainland China). Order mirrors the comparison table.
    private var benefitRows: [BenefitRow] {
        let socialEnabled = featureFlags.socialEnabled
        var rows: [BenefitRow] = []
        if socialEnabled {
            rows.append(BenefitRow(icon: "camera.fill",         key: "membership_benefit_photos"))
            rows.append(BenefitRow(icon: "person.2.fill",       key: "membership_benefit_friends"))
            rows.append(BenefitRow(icon: "envelope.fill",       key: "membership_benefit_postcard"))
        }
        rows.append(BenefitRow(icon: "globe",                   key: "membership_benefit_globe"))
        rows.append(BenefitRow(icon: "icloud.fill",             key: "membership_benefit_icloud"))
        rows.append(BenefitRow(icon: "square.and.arrow.up",     key: "membership_benefit_gpx"))
        rows.append(BenefitRow(icon: "map.fill",                key: "membership_benefit_map"))
        rows.append(BenefitRow(icon: "bag.fill",                key: "membership_benefit_equipment_coins"))
        rows.append(BenefitRow(icon: "sparkles",                key: "membership_benefit_more_features"))
        return rows
    }

    private var activeBenefitsCard: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text(L10n.t("membership_your_benefits"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(FigmaTheme.subtext)
                Spacer()
                if let exp = membership.expirationDate {
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateStyle = .medium
                        return f
                    }()
                    Text(String(format: L10n.t("membership_expires_format"), formatter.string(from: exp)))
                        .font(.system(size: 12))
                        .foregroundColor(FigmaTheme.subtext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(FigmaTheme.mutedBackground)

            // Benefits list
            ForEach(Array(benefitRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                        .frame(width: 22)
                    Text(L10n.t(row.key))
                        .font(.system(size: 14))
                        .foregroundColor(FigmaTheme.text)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(FigmaTheme.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if index < benefitRows.count - 1 {
                        FigmaTheme.border.frame(height: 1)
                    }
                }
            }

            // Manage subscription link
            FigmaTheme.border.frame(height: 1)
            Button {
                Task {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        try? await AppStore.showManageSubscriptions(in: windowScene)
                    }
                }
            } label: {
                Text(L10n.t("membership_manage_subscription"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
        }
        .background(FigmaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    // MARK: - Comparison Table (free users)

    private var comparisonTable: some View {
        // Social-gated rows (friends / postcard / photos-per-journey) are hidden
        // in restricted storefront regions (e.g. mainland China) where those
        // features are not offered.
        let socialEnabled = featureFlags.socialEnabled
        return VStack(spacing: 0) {
            comparisonHeader
            if socialEnabled {
                // — Unlimited upgrades first —
                comparisonRow(
                    feature: L10n.t("membership_compare_friends"),
                    freeValue: "5",
                    premiumValue: L10n.t("membership_compare_unlimited")
                )
                comparisonRow(
                    feature: L10n.t("membership_compare_postcard"),
                    freeValue: "1/3",
                    premiumValue: L10n.t("membership_compare_unlimited"),
                    infoKey: "postcard"
                )
                // — Other numeric limits —
                comparisonRow(
                    feature: L10n.t("membership_compare_photos"),
                    freeValue: "6",
                    premiumValue: "12",
                    infoKey: "photos"
                )
            }
            // — Premium-only features —
            comparisonRow(
                feature: L10n.t("membership_compare_globe"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_icloud"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_gpx"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_republish"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_map_theme"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_equipment_coins"),
                freeValue: nil,
                premiumValue: "check"
            )
            comparisonRow(
                feature: L10n.t("membership_compare_more_features"),
                freeValue: nil,
                premiumValue: "check",
                isLast: true
            )
        }
        .background(FigmaTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private var comparisonHeader: some View {
        HStack(spacing: 0) {
            Text(L10n.t("membership_compare_feature"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(FigmaTheme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.t("membership_compare_free"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(FigmaTheme.subtext)
                .frame(width: 60, alignment: .center)

            Text(L10n.t("membership_compare_premium"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(FigmaTheme.primary)
                .frame(width: 60, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FigmaTheme.mutedBackground)
    }

    private func comparisonRow(
        feature: String,
        freeValue: String?,
        premiumValue: String,
        infoKey: String? = nil,
        isLast: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(feature)
                    .font(.system(size: 13))
                    .foregroundColor(FigmaTheme.text)
                if let infoKey {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            activeInfoKey = activeInfoKey == infoKey ? nil : infoKey
                        }
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13))
                            .foregroundColor(FigmaTheme.subtext.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            cellContent(value: freeValue, isPremium: false)
                .frame(width: 60, alignment: .center)

            cellContent(value: premiumValue, isPremium: true)
                .frame(width: 60, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                FigmaTheme.border.frame(height: 1)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let infoKey, activeInfoKey == infoKey {
                Text(L10n.t("membership_info_\(infoKey)"))
                    .font(.system(size: 11))
                    .foregroundColor(FigmaTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: 260, alignment: .leading)
                    .background(FigmaTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .offset(x: 4, y: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                    .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private func cellContent(value: String?, isPremium: Bool) -> some View {
        if let value {
            if value == "check" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(isPremium ? FigmaTheme.primary : FigmaTheme.subtext)
            } else {
                Text(value)
                    .font(.system(size: 13, weight: isPremium ? .bold : .regular))
                    .foregroundColor(isPremium ? FigmaTheme.primary : FigmaTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(FigmaTheme.subtext.opacity(0.35))
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            if !products.isEmpty {
                ForEach(sortedProducts, id: \.id) { product in
                    planCard(product: product)
                }
            } else if productsLoadFinished {
                fallbackPlanCard(
                    id: MembershipStore.subscriptionProductID,
                    name: L10n.t("membership_plan_monthly"),
                    period: L10n.t("membership_period_monthly"),
                    price: "$2.99",
                    isYearly: false
                )
                fallbackPlanCard(
                    id: MembershipStore.yearlyProductID,
                    name: L10n.t("membership_plan_yearly"),
                    period: L10n.t("membership_period_yearly"),
                    price: "$19.99",
                    isYearly: true
                )
            } else {
                ProgressView()
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func fallbackPlanCard(id: String, name: String, period: String, price: String, isYearly: Bool) -> some View {
        let isSelected = selectedProductID == id
        return Button {
            selectedProductID = id
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? FigmaTheme.primary : FigmaTheme.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(FigmaTheme.primary)
                            .frame(width: 13, height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)

                        if isYearly {
                            Text(L10n.t("membership_save_badge"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FigmaTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(period)
                        .font(.system(size: 12))
                        .foregroundColor(FigmaTheme.subtext)
                }

                Spacer()

                Text(price)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isSelected ? FigmaTheme.primary : FigmaTheme.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FigmaTheme.primary : FigmaTheme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func planCard(product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id == MembershipStore.yearlyProductID

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? FigmaTheme.primary : FigmaTheme.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(FigmaTheme.primary)
                            .frame(width: 13, height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)

                        if isYearly {
                            Text(L10n.t("membership_save_badge"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FigmaTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }

                    if let sub = product.subscription {
                        Text(subscriptionPeriodText(sub.subscriptionPeriod))
                            .font(.system(size: 12))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isSelected ? FigmaTheme.primary : FigmaTheme.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FigmaTheme.primary : FigmaTheme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore & Terms

    private var restoreAndTerms: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    try? await AppStore.sync()
                    await membership.refreshEntitlement()
                }
            } label: {
                Text(L10n.t("membership_restore_purchases"))
                    .font(.system(size: 14))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Text(L10n.t("membership_auto_renew_note"))
                .font(.system(size: 11))
                .foregroundColor(FigmaTheme.subtext.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 8)
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
                // Stay on page to show active status
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
