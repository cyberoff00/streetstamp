//
//  CoinService.swift
//  StreetStamps
//
//  Routes coin reads/writes by user identity:
//  - Guest user: iOS UserDefaults (per active local profile) is authoritative.
//  - Account user: backend Postgres is authoritative; SDK keeps a local cache
//    so UI reads stay synchronous and don't block.
//
//  Membership stays in RevenueCat — this service does not touch entitlements.
//

import Foundation
import Combine

@MainActor
final class CoinService: ObservableObject {
    static let shared = CoinService()

    /// Cached balance. UI reads this synchronously.
    /// Hydrated from UserDefaults (guest) or from backend (account) at bootstrap
    /// and after every grant/spend/merge call.
    @Published private(set) var balance: Int = 0

    /// Source identifier for `mergeFromExternal`. Must match the allowlist
    /// the backend enforces on `/v1/coins/merge`.
    enum MergeSource: String {
        case guestUpgrade = "guest_upgrade"
        case deviceTransfer = "device_transfer"
        case userDefaultsMigration = "userdefaults_migration"
    }

    private weak var sessionStore: UserSessionStore?
    private let migrationDoneKeyPrefix = "streetstamps.coins.postgres_migration_done.v1"

    private init() {}

    func bindSessionStore(_ store: UserSessionStore) {
        self.sessionStore = store
        // Seed the cache from local storage so the first UI read isn't 0
        // before `bootstrap()` finishes the network round-trip.
        balance = EquipmentEconomyStore.load().coins
    }

    private var isAccountUser: Bool {
        guard let s = sessionStore, let uid = s.accountUserID, !uid.isEmpty else { return false }
        return true
    }

    private var accessToken: String? {
        guard let token = sessionStore?.currentAccessToken, !token.isEmpty else { return nil }
        return token
    }

    /// Called on app launch and after login/logout transitions. For account
    /// users, runs the one-shot UserDefaults→Postgres migration if needed
    /// (idempotent via a stable merge token), then refreshes the cached balance
    /// from the server.
    func bootstrap() async {
        if isAccountUser, let accountID = sessionStore?.accountUserID {
            await migrateLocalIfNeeded(accountID: accountID)
            await retryPendingGrants()
            await refreshFromBackend()
        } else {
            balance = EquipmentEconomyStore.load().coins
        }
    }

    /// Refreshes the local cache from the authoritative source. Safe to call
    /// from anywhere that needs a fresh balance (e.g. settling into a screen
    /// that displays coins after returning from background).
    func refresh() async {
        if isAccountUser {
            await retryPendingGrants()
            await refreshFromBackend()
        } else {
            balance = EquipmentEconomyStore.load().coins
        }
    }

    /// Replays grants that failed after the user paid (IAP) or earned them
    /// (journey reward). Safe to call repeatedly: every queued grant carries a
    /// dedupe token the server credits at most once. Entries stay queued until
    /// a request succeeds; one network failure aborts the pass (next
    /// bootstrap/refresh retries).
    private func retryPendingGrants() async {
        guard isAccountUser,
              let accountID = sessionStore?.accountUserID, !accountID.isEmpty,
              let token = accessToken else { return }
        for entry in PendingCoinGrantQueue.entries(forAccount: accountID) {
            do {
                let newBalance = try await BackendAPIClient.shared.grantCoins(
                    amount: entry.amount,
                    reason: entry.reason,
                    token: token,
                    dedupeToken: entry.dedupeToken
                )
                balance = newBalance
                PendingCoinGrantQueue.remove(dedupeToken: entry.dedupeToken)
            } catch {
                break
            }
        }
    }

    /// Credit coins. Used by journey rewards, premium welcome bonus, future
    /// step milestones, IAP coin-pack callbacks, etc. Reason is logged in the
    /// `coin_transactions` audit table (account path only) or ignored locally.
    /// Returns true on success.
    @discardableResult
    func grant(_ amount: Int, reason: String, dedupeToken: String? = nil) async -> Bool {
        guard amount > 0 else { return true }
        if isAccountUser, let token = accessToken {
            do {
                let newBalance = try await BackendAPIClient.shared.grantCoins(
                    amount: amount, reason: reason, token: token, dedupeToken: dedupeToken
                )
                balance = newBalance
                return true
            } catch {
                // Only queue grants that carry an idempotency token: retrying
                // a tokenless grant after a lost-response failure could
                // double-credit (the server may have already applied it).
                if let dedupeToken, !dedupeToken.isEmpty,
                   let accountID = sessionStore?.accountUserID, !accountID.isEmpty {
                    PendingCoinGrantQueue.enqueue(PendingCoinGrant(
                        amount: amount,
                        reason: reason,
                        dedupeToken: dedupeToken,
                        accountUserID: accountID
                    ))
                }
                return false
            }
        }
        var economy = EquipmentEconomyStore.load()
        economy.coins += amount
        EquipmentEconomyStore.save(economy)
        balance = economy.coins
        return true
    }

    /// Deduct coins. Returns false if insufficient balance (server enforces
    /// the non-negative invariant atomically). Use this for equipment buys
    /// and refund clawbacks.
    func spend(_ amount: Int, reason: String) async -> Bool {
        guard amount > 0 else { return true }
        if isAccountUser, let token = accessToken {
            do {
                let result = try await BackendAPIClient.shared.spendCoins(
                    amount: amount, reason: reason, token: token
                )
                balance = result.balance
                return result.ok
            } catch {
                return false
            }
        }
        var economy = EquipmentEconomyStore.load()
        guard economy.coins >= amount else { return false }
        economy.coins -= amount
        EquipmentEconomyStore.save(economy)
        balance = economy.coins
        return true
    }

    /// Import coins from a one-shot external source. The same `mergeToken`
    /// played back is a no-op so retries cannot double-credit. Used by:
    /// - guest→account upgrade (token = stable per guest profile)
    /// - device-to-device transfer (token = archive's transfer ID)
    /// - one-shot UserDefaults migration (token = "userdefaults_migration_<accountID>")
    /// Guest callers don't have a backend account; their merge just adds to
    /// the local economy (no idempotency needed since there's no server).
    @discardableResult
    func mergeFromExternal(amount: Int, source: MergeSource, token mergeToken: String) async -> Int {
        guard amount > 0 else { return balance }
        if isAccountUser, let access = accessToken {
            do {
                let newBalance = try await BackendAPIClient.shared.mergeCoins(
                    amount: amount, source: source.rawValue, mergeToken: mergeToken, accessToken: access
                )
                balance = newBalance
                return newBalance
            } catch {
                return balance
            }
        }
        var economy = EquipmentEconomyStore.load()
        economy.coins += amount
        EquipmentEconomyStore.save(economy)
        balance = economy.coins
        return economy.coins
    }

    // MARK: - Internals

    private func migrateLocalIfNeeded(accountID: String) async {
        let key = "\(migrationDoneKeyPrefix).\(accountID)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let localCoins = EquipmentEconomyStore.load().coins
        if localCoins > 0 {
            // Stable token tied to the account ID. The server's `coin_merge_tokens`
            // PK ensures this only credits once even if we retry across launches.
            let mergeToken = "userdefaults_migration_\(accountID)"
            _ = await mergeFromExternal(
                amount: localCoins,
                source: .userDefaultsMigration,
                token: mergeToken
            )
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func refreshFromBackend() async {
        guard let token = accessToken else { return }
        if let remote = try? await BackendAPIClient.shared.fetchCoinBalance(token: token) {
            balance = remote
        }
    }
}
