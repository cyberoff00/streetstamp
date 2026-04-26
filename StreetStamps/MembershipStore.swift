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
}

// MARK: - Store

@MainActor
final class MembershipStore: ObservableObject {
    static let shared = MembershipStore()

    @Published private(set) var tier: MembershipTier = .free
    @Published private(set) var expirationDate: Date?

    private let tierKey = "streetstamps.membership.tier"
    private let expirationKey = "streetstamps.membership.expiration"
    private let sandboxPurchasedOnceKey = "streetstamps.membership.sandbox_purchased_once"
    static let welcomeBonusGrantedKey = "streetstamps.membership.welcome_bonus_granted"

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

    private var transactionListener: Task<Void, Never>?

    var isPremium: Bool {
        guard tier == .premium else { return false }
        // Treat a cached-premium tier whose expiration has already passed as
        // free until refreshEntitlement() syncs the real StoreKit state. This
        // prevents users from continuing to access premium features in the
        // window between subscription expiry and Transaction.updates delivery.
        if let exp = expirationDate, exp < Date() { return false }
        return true
    }

    private init() {
        // Restore cached tier from UserDefaults
        if let raw = UserDefaults.standard.string(forKey: tierKey),
           let cached = MembershipTier(rawValue: raw) {
            tier = cached
        }
        if let ts = UserDefaults.standard.object(forKey: expirationKey) as? Double, ts > 0 {
            expirationDate = Date(timeIntervalSince1970: ts)
        }

        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
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

    var isMapboxStyleLocked: Bool {
        MembershipTierConfig.isMapboxStyleLocked(for: tier)
    }

    // MARK: - StoreKit 2 Subscription Verification

    /// App Store subscription product ID for premium membership.
    static let subscriptionProductID = "com.streetstamps.premium.monthly"
    static let yearlyProductID = "com.streetstamps.premium.yearly"
    private static var subscriptionProductIDs: Set<String> {
        [subscriptionProductID, yearlyProductID]
    }

    /// Check current entitlement on launch or after purchase.
    func refreshEntitlement() async {
        var foundActive = false
        var latestExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.subscriptionProductIDs.contains(transaction.productID) {
                foundActive = true
                if let exp = transaction.expirationDate {
                    if latestExpiration == nil || exp > latestExpiration! {
                        latestExpiration = exp
                    }
                }
            }
        }

        let isSandbox = Self.isSandboxEnvironment

        if foundActive {
            let wasFreeBefore = tier == .free
            var expiration = latestExpiration
            if isSandbox {
                // Reviewer/tester completed a real purchase flow — extend the
                // 5-minute sandbox window to 30 days so they keep premium for
                // the rest of the session. See sandboxGrantSeconds doc.
                expiration = Date().addingTimeInterval(Self.sandboxGrantSeconds)
                UserDefaults.standard.set(true, forKey: sandboxPurchasedOnceKey)
            }
            applyTier(.premium, expiration: expiration)
            if wasFreeBefore && !welcomeBonusGranted {
                awardWelcomeBonus()
            }
        } else if isSandbox && UserDefaults.standard.bool(forKey: sandboxPurchasedOnceKey) {
            // Sandbox auto-renewal exhausted (max 6 cycles) but tester
            // previously completed the purchase flow — preserve premium so
            // the test build doesn't flip back to free mid-session.
            applyTier(.premium, expiration: Date().addingTimeInterval(Self.sandboxGrantSeconds))
        } else {
            applyTier(.free, expiration: nil)
        }
    }

    /// Award the one-time 1500 coin welcome bonus on first premium subscription.
    private func awardWelcomeBonus() {
        var economy = EquipmentEconomyStore.load()
        economy.coins += MembershipTierConfig.premiumWelcomeBonus
        EquipmentEconomyStore.save(economy)
        markWelcomeBonusGranted()
        showWelcomeBonusAlert = true
    }

    /// Set by `awardWelcomeBonus` so the UI can show a congratulations alert.
    @Published var showWelcomeBonusAlert = false

    /// Purchase a subscription product.
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlement()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
