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

    private static let lastRewardedMilestoneKey = "streetstamps.steps.coin.last_rewarded_milestone"

    struct Result {
        let coinsAwarded: Int
        let milestonesReached: Int
    }

    /// Check if new milestones have been reached since the last reward, and grant coins.
    /// Returns the number of coins awarded (0 if no new milestones).
    @MainActor
    static func checkAndReward(currentSteps: Int) -> Result {
        let currentMilestone = currentSteps / stepsPerMilestone
        let lastRewarded = UserDefaults.standard.integer(forKey: lastRewardedMilestoneKey)

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
        UserDefaults.standard.set(currentMilestone, forKey: lastRewardedMilestoneKey)

        return Result(coinsAwarded: totalCoins, milestonesReached: newMilestones)
    }
}
