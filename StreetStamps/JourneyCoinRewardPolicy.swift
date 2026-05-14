//
//  JourneyCoinRewardPolicy.swift
//  StreetStamps
//
//  Awards coins for completed journeys.
//  Every full kilometer earns 10 coins, capped at 100 coins per journey.
//

import Foundation

enum JourneyCoinRewardPolicy {

    static let coinsPerKm = 10
    static let maxCoinsPerJourney = 100

    /// Persists which journey IDs have already been credited, so re-finalizing
    /// or restart-mid-finalize cannot grant a second reward for the same trip.
    private static let rewardedJourneysKey = "streetstamps.journey.coin.rewarded_ids.v1"

    /// Pure reward calculation. Returns 0 for journeys under 1 km.
    static func compute(distanceMeters: Double) -> Int {
        guard distanceMeters > 0 else { return 0 }
        let km = Int(distanceMeters / 1000.0)
        return min(maxCoinsPerJourney, km * coinsPerKm)
    }

    /// Credits the journey-completion bonus once per `journeyID`.
    /// Returns the coin amount awarded (0 if already rewarded or under threshold).
    /// Synchronous return so the completion animation can show the number
    /// immediately; the actual coin credit fires asynchronously to the
    /// CoinService (which routes to backend or UserDefaults).
    ///
    /// Idempotency is the UserDefaults marker — set BEFORE the async grant
    /// kicks off so a retry-after-failure cannot double-credit.
    @MainActor
    static func checkAndReward(journeyID: String, distanceMeters: Double) -> Int {
        let amount = compute(distanceMeters: distanceMeters)
        guard amount > 0, !journeyID.isEmpty else { return 0 }

        var rewarded = Set(UserDefaults.standard.stringArray(forKey: rewardedJourneysKey) ?? [])
        guard !rewarded.contains(journeyID) else { return 0 }

        rewarded.insert(journeyID)
        UserDefaults.standard.set(Array(rewarded), forKey: rewardedJourneysKey)

        // Fire and forget the actual credit. UI got `amount` already; if the
        // backend call fails the user keeps the marker (no double-credit on
        // future finalize) but loses the coins. Acceptable tradeoff at this
        // scale; recoverable via audit log if a customer complains.
        Task { @MainActor in
            await CoinService.shared.grant(amount, reason: "journey_reward:\(journeyID)")
        }

        return amount
    }
}
