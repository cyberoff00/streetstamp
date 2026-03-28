//
//  StepCoinRewardPolicy.swift
//  StreetStamps
//
//  Awards coins for step milestones.
//  Every 10,000 steps: free users earn 10 coins, premium users earn 50 coins.
//

import Foundation

enum StepCoinRewardPolicy {

    static let stepsPerMilestone = 10_000

    private static let lastRewardedMilestoneKeyBase = "streetstamps.steps.coin.last_rewarded_milestone"

    private static func lastRewardedMilestoneKey(for userID: String) -> String {
        userID.isEmpty ? lastRewardedMilestoneKeyBase : "\(lastRewardedMilestoneKeyBase).user.\(userID)"
    }

    struct Result {
        let coinsAwarded: Int
        let milestonesReached: Int
    }

    /// Check if new milestones have been reached since the last reward, and grant coins.
    /// Returns the number of coins awarded (0 if no new milestones).
    @MainActor
    static func checkAndReward(currentSteps: Int, userID: String) -> Result {
        let currentMilestone = currentSteps / stepsPerMilestone
        let key = lastRewardedMilestoneKey(for: userID)
        let lastRewarded = UserDefaults.standard.integer(forKey: key)

        guard currentMilestone > lastRewarded else {
            return Result(coinsAwarded: 0, milestonesReached: 0)
        }

        let newMilestones = currentMilestone - lastRewarded
        let coinsPerMilestone = MembershipStore.shared.coinsPerStepMilestone
        let totalCoins = newMilestones * coinsPerMilestone

        // Credit coins
        var economy = EquipmentEconomyStore.load()
        economy.coins += totalCoins
        EquipmentEconomyStore.save(economy)

        // Update last rewarded milestone
        UserDefaults.standard.set(currentMilestone, forKey: key)

        return Result(coinsAwarded: totalCoins, milestonesReached: newMilestones)
    }
}
