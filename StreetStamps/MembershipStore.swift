//
//  MembershipStore.swift
//  StreetStamps
//
//  Central membership state and tier-based limit configuration.
//  All membership-gated limits should be read from MembershipTierConfig
//  so that changing tier automatically adjusts all boundaries.
//

import Foundation
import StoreKit
import Combine
import RevenueCat

// MARK: - Tier Definition

enum MembershipTier: String, Codable, Equatable {
    case free
    case premium
}

// MARK: - Tier Config (all limits live here)

enum MembershipTierConfig {

    // MARK: Journey Photos

    static func maxJourneyPhotos(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 6
        case .premium: return 12
        }
    }

    /// Per-memory / per-overall-memory photo cap (same for all tiers).
    static func maxPhotosPerMemory(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 2
        case .premium: return 2
        }
    }

    // MARK: Friends

    static func maxFriends(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 5
        case .premium: return Int.max
        }
    }

    // MARK: Mapbox Globe

    static func globeViewEnabled(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return false
        case .premium: return true
        }
    }

    // MARK: Public Journey Re-publish After Edit

    static func canRepublishEditedJourney(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return false
        case .premium: return true
        }
    }

    // MARK: Postcards

    /// Max postcards per city (base, before journey-count bonus).
    static func postcardPerCityBase(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 1
        case .premium: return 2
        }
    }

    /// Max distinct friends a user can send postcards to (base).
    static func postcardMaxFriends(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 3
        case .premium: return 10
        }
    }

    // MARK: Coins (step reward)

    /// Coins earned per 10,000 steps.
    static func coinsPerStepMilestone(for tier: MembershipTier) -> Int {
        switch tier {
        case .free:    return 10
        case .premium: return 50
        }
    }

    /// One-time welcome bonus when user first subscribes.
    static let premiumWelcomeBonus: Int = 1500

    // MARK: iCloud Sync

    static func iCloudSyncEnabled(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return false
        case .premium: return true
        }
    }

    // MARK: GPX Export

    static func gpxExportEnabled(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return false
        case .premium: return true
        }
    }

    // MARK: Map Appearance

    /// Free users can only use Apple Maps styles; Mapbox styles require premium or active trial.
    static func isMapboxStyleLocked(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return !MapLayerStyle.isMapboxTrialActive
        case .premium: return false
        }
    }

    // MARK: Map Matching (snap journey to road network)

    /// Premium-only feature. Cost-bearing (Mapbox API per-request pricing).
    /// Non-premium users see the journey's raw / corrected route; premium users
    /// get the route snapped to actual roads after journey completion.
    static func mapMatchingEnabled(for tier: MembershipTier) -> Bool {
        switch tier {
        case .free:    return false
        case .premium: return true
        }
    }
}

// MARK: - Store

@MainActor
final class MembershipStore: NSObject, ObservableObject {
    static let shared = MembershipStore()

    @Published private(set) var tier: MembershipTier = .free
    @Published private(set) var expirationDate: Date?

    /// Set when a refund is detected so the UI can present a notice that
    /// the welcome bonus coins have been clawed back.
    @Published var showRefundProcessedAlert = false

    private let tierKey = "streetstamps.membership.tier"
    private let expirationKey = "streetstamps.membership.expiration"
    private let sandboxPurchasedOnceKey = "streetstamps.membership.sandbox_purchased_once"
    nonisolated static let welcomeBonusGrantedKey = "streetstamps.membership.welcome_bonus_granted"

    /// RevenueCat entitlement identifier. Configured in the RevenueCat
    /// dashboard with both monthly and yearly products attached.
    static let entitlementID = "premium"

    /// TestFlight builds and App Store review use sandbox receipts. Production
    /// App Store users get a regular `receipt`. This is the standard way to
    /// distinguish test/review traffic from real paying users.
    private static var isSandboxEnvironment: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Sandbox compresses subscriptions to 5 min (monthly) / 1 hour (yearly)
    /// and stops auto-renewing after 6 cycles. We override that with a 30-day
    /// local grant so TestFlight testers and reviewers can use premium across
    /// a full review session without re-subscribing.
    private static let sandboxGrantSeconds: TimeInterval = 86400 * 30

    var isPremium: Bool {
        guard tier == .premium else { return false }
        // Treat a cached-premium tier whose expiration has already passed as
        // free until refreshEntitlement() syncs real entitlement state.
        if let exp = expirationDate, exp < Date() { return false }
        return true
    }

    private static let revenueCatInitialImportKey = "streetstamps.membership.revenuecat_initial_import_done"

    private override init() {
        super.init()
        // Restore cached tier from UserDefaults so the first frame doesn't
        // flash "free" while RevenueCat fetches the real customerInfo.
        if let raw = UserDefaults.standard.string(forKey: tierKey),
           let cached = MembershipTier(rawValue: raw) {
            tier = cached
        }
        if let ts = UserDefaults.standard.object(forKey: expirationKey) as? Double, ts > 0 {
            expirationDate = Date(timeIntervalSince1970: ts)
        }

        Purchases.shared.delegate = self

        // First launch with RevenueCat: import existing StoreKit transactions
        // so users who subscribed pre-migration appear in RevenueCat with the
        // correct entitlement. Only mark complete on successful restore so a
        // transient network failure doesn't permanently strand the user with
        // their real subscription invisible to RevenueCat.
        if !UserDefaults.standard.bool(forKey: Self.revenueCatInitialImportKey) {
            Task {
                do {
                    _ = try await Purchases.shared.restorePurchases()
                    UserDefaults.standard.set(true, forKey: Self.revenueCatInitialImportKey)
                } catch {
                    // Will retry on next launch.
                }
            }
        }
    }

    // MARK: - Convenience Accessors

    var maxJourneyPhotos: Int { MembershipTierConfig.maxJourneyPhotos(for: tier) }
    var maxPhotosPerMemory: Int { MembershipTierConfig.maxPhotosPerMemory(for: tier) }
    var maxFriends: Int { MembershipTierConfig.maxFriends(for: tier) }
    var globeViewEnabled: Bool { MembershipTierConfig.globeViewEnabled(for: tier) }
    var canRepublishEditedJourney: Bool { MembershipTierConfig.canRepublishEditedJourney(for: tier) }
    var postcardPerCityBase: Int { MembershipTierConfig.postcardPerCityBase(for: tier) }
    var postcardMaxFriends: Int { MembershipTierConfig.postcardMaxFriends(for: tier) }
    var coinsPerStepMilestone: Int { MembershipTierConfig.coinsPerStepMilestone(for: tier) }
    var iCloudSyncEnabled: Bool { MembershipTierConfig.iCloudSyncEnabled(for: tier) }
    var gpxExportEnabled: Bool { MembershipTierConfig.gpxExportEnabled(for: tier) }
    var mapMatchingEnabled: Bool { MembershipTierConfig.mapMatchingEnabled(for: tier) }

    var isMapboxStyleLocked: Bool {
        MembershipTierConfig.isMapboxStyleLocked(for: tier)
    }

    // MARK: - Subscription Verification (via RevenueCat)

    /// App Store subscription product IDs. Kept exposed because
    /// MembershipSubscriptionView still loads StoreKit Products by ID for
    /// price/display, and identifies the yearly plan for the "save" badge.
    static let subscriptionProductID = "com.streetstamps.premium.monthly"
    static let yearlyProductID = "com.streetstamps.premium.yearly"

    /// Check current entitlement on launch or after purchase.
    /// Source of truth is RevenueCat's customerInfo, which reflects Apple's
    /// real-time subscription state across devices and survives transient
    /// StoreKit sync gaps (e.g. during region change).
    func refreshEntitlement() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
        } catch {
            // RevenueCat fetch failed (no network, server down, etc.).
            // Keep cached tier — the cache fallback in applyCustomerInfo's
            // free branch already handles the "stale but still in paid period"
            // case, and silently ignoring lets the next refresh recover.
        }
    }

    /// Apply a RevenueCat customerInfo snapshot. Detects natural transitions
    /// (free → premium, premium → free at expiration) and revocation events
    /// (refund, family sharing removal). Revocation goes through the dedicated
    /// `handleRevocation` path so welcome bonus coins are clawed back; natural
    /// expiration leaves earned coins alone.
    private func applyCustomerInfo(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementID]
        let isActive = entitlement?.isActive == true
        let isSandbox = Self.isSandboxEnvironment

        if isActive, let entitlement = entitlement {
            let wasFreeBefore = tier == .free
            var expiration = entitlement.expirationDate
            if isSandbox {
                // Reviewer/tester completed a real purchase flow — extend the
                // 5-minute sandbox window to 30 days so they keep premium for
                // the rest of the session. See sandboxGrantSeconds doc.
                expiration = Date().addingTimeInterval(Self.sandboxGrantSeconds)
                UserDefaults.standard.set(true, forKey: sandboxPurchasedOnceKey)
            }
            applyTier(.premium, expiration: expiration)
            if wasFreeBefore {
                autoEnableICloudSyncIfNeeded()
                // Strategy A: skip the welcome bonus when the entitlement
                // doesn't auto-renew. Free offer codes (press / influencer
                // gifts) typically activate as non-renewing — we still give
                // them premium access but withhold the 1500-coin freebie that
                // would otherwise dilute the gear economy. Trials and intro
                // offers still set willRenew=true and remain eligible.
                if !welcomeBonusGranted && entitlement.willRenew {
                    awardWelcomeBonus()
                }
            }
            return
        }

        if isSandbox && UserDefaults.standard.bool(forKey: sandboxPurchasedOnceKey) {
            // Sandbox auto-renewal exhausted (max 6 cycles) but tester
            // previously completed the purchase flow — preserve premium so
            // the test build doesn't flip back to free mid-session.
            applyTier(.premium, expiration: Date().addingTimeInterval(Self.sandboxGrantSeconds))
            return
        }

        // Revocation detection: previously premium, RevenueCat now reports
        // inactive, but the entitlement's recorded expiration date is still
        // in the future → refund or family sharing removal. Coins clawed back.
        let wasPremium = tier == .premium
        if wasPremium, let recordedExp = entitlement?.expirationDate, recordedExp > Date() {
            handleRevocation()
            return
        }

        // Cache fallback: RevenueCat sees no entitlement, but our cached
        // expiration (last confirmed by Apple) is still in the future. This
        // covers transient StoreKit sync gaps after Apple ID region change
        // or brief RevenueCat outages. We stop honoring the cache once the
        // recorded expiration naturally passes.
        if let cachedExp = expirationDate, cachedExp > Date() {
            return
        }

        applyTier(.free, expiration: nil)
    }

    /// Revoke premium immediately and roll back the welcome bonus.
    /// Triggered when a refund or family sharing removal cuts a subscription
    /// short. Coins the user already spent above the granted bonus stay at
    /// zero — we cannot retroactively reclaim consumed coins.
    /// The `welcomeBonusGranted` marker is intentionally NOT reset: a user
    /// who subscribes, spends the bonus on gear, then refunds would otherwise
    /// be able to re-subscribe and farm an unlimited supply of free gear.
    private func handleRevocation() {
        applyTier(.free, expiration: nil)
        if welcomeBonusGranted {
            // Try to claw back the 1500-coin bonus. CoinService.spend returns
            // false if the user has already spent below that — we don't push
            // them below zero (server enforces non-negative anyway).
            Task { @MainActor in
                _ = await CoinService.shared.spend(
                    MembershipTierConfig.premiumWelcomeBonus,
                    reason: "premium_revocation"
                )
            }
        }
        showRefundProcessedAlert = true
    }

    /// Award the one-time 1500 coin welcome bonus on first premium subscription.
    private func awardWelcomeBonus() {
        markWelcomeBonusGranted()
        Task { @MainActor in
            await CoinService.shared.grant(
                MembershipTierConfig.premiumWelcomeBonus,
                reason: "premium_welcome_bonus"
            )
        }
        showWelcomeBonusAlert = true
    }

    /// Set by `awardWelcomeBonus` so the UI can show a congratulations alert.
    @Published var showWelcomeBonusAlert = false

    /// Set when premium just activated and iCloud sync was auto-enabled.
    /// UI presents a follow-up alert; AppRuntimeCoordinator triggers the
    /// force-full upload. Both consumers clear it after handling.
    @Published var pendingICloudAutoEnableNotice = false

    /// Flip the iCloud sync flag on first activation per premium cycle so
    /// the user gets the feature without manually toggling. Idempotent: if
    /// the user has already turned it on (or off then on) this is a no-op.
    private func autoEnableICloudSyncIfNeeded() {
        guard !AppSettings.isICloudSyncEnabled else { return }
        UserDefaults.standard.set(true, forKey: AppSettings.iCloudSyncEnabledKey)
        // Persist the full-upload intent so it survives if the first attempt is
        // interrupted by an app kill or iCloud being temporarily unavailable.
        UserDefaults.standard.set(true, forKey: AppSettings.pendingFullSyncAfterAutoEnableKey)
        pendingICloudAutoEnableNotice = true
    }

    /// Purchase a subscription product. RevenueCat finishes the transaction
    /// for us and pushes the resulting customerInfo through the delegate, so
    /// we just inspect the returned snapshot to report success. The view layer
    /// loads StoreKit Products directly for price/display and passes one in;
    /// RevenueCat needs its own StoreProduct wrapper, hence the conversion.
    func purchase(_ product: Product) async throws -> Bool {
        let storeProduct = StoreProduct(sk2Product: product)
        let result = try await Purchases.shared.purchase(product: storeProduct)
        if result.userCancelled { return false }
        applyCustomerInfo(result.customerInfo)
        return result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
    }

    /// Restore purchases on demand (Settings / paywall "Restore" button).
    /// Forces a sync with Apple and re-applies the resulting customerInfo.
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        applyCustomerInfo(info)
    }

    /// Present Apple's offer code redemption sheet. Called from paywall and
    /// settings; the redeemed offer flows back through Transaction.updates →
    /// PurchasesDelegate so we don't need to handle the result here.
    @available(iOS 14.0, *)
    func presentOfferCodeRedemption() async {
        do {
            try await Purchases.shared.presentCodeRedemptionSheet()
        } catch {
            // User cancelled or sheet unavailable — nothing to do.
        }
    }

    // MARK: - Internal

    private func applyTier(_ newTier: MembershipTier, expiration: Date?) {
        let wasPremium = (tier == .premium)
        tier = newTier
        expirationDate = expiration
        UserDefaults.standard.set(newTier.rawValue, forKey: tierKey)
        if let exp = expiration {
            UserDefaults.standard.set(exp.timeIntervalSince1970, forKey: expirationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: expirationKey)
        }
        if wasPremium && newTier == .free {
            revokePersistedPremiumEntitlements()
        }
    }

    /// Persisted premium-only state that does not auto-revoke from read-time
    /// gates. Read-time gates (globe zoom, gpx export, photo cap, etc.) flip
    /// automatically once `tier` becomes `.free`; only these UserDefaults-backed
    /// switches stay "on" after the tier flips and must be cleared explicitly.
    private func revokePersistedPremiumEntitlements() {
        UserDefaults.standard.set(false, forKey: AppSettings.iCloudSyncEnabledKey)
        MapLayerStyle.revertToDefaultIfNeeded()
    }

    /// Whether the welcome bonus has already been granted for the active user.
    var welcomeBonusGranted: Bool {
        UserScopedProfileStateStore.currentWelcomeBonusGranted()
    }

    /// Mark the welcome bonus as granted. Call this from the coin-awarding
    /// site (e.g. EquipmentView) after actually crediting the coins, so the
    /// bonus is only given once.
    func markWelcomeBonusGranted() {
        UserScopedProfileStateStore.saveCurrentWelcomeBonusGranted(true)
    }

}

// MARK: - PurchasesDelegate

extension MembershipStore: PurchasesDelegate {
    /// RevenueCat pushes a fresh customerInfo whenever entitlement state
    /// changes — initial fetch, purchase, renewal, refund, family sharing
    /// changes. This is the only listener we need; the old StoreKit
    /// `Transaction.updates` task is no longer required.
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.applyCustomerInfo(customerInfo)
        }
    }
}
