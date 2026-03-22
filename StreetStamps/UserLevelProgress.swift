import Foundation
import SwiftUI

struct UserLevelProgress: Equatable {
    let completedJourneys: Int
    let level: Int
    let journeysIntoCurrentLevel: Int
    let journeysRequiredThisLevel: Int
    let journeysRemainingToNextLevel: Int
    let progress: Double

    static func from(journeys: [JourneyRoute]) -> UserLevelProgress {
        from(completedJourneyCount: journeys.filter { $0.isCompleted && $0.distance >= 1000 }.count)
    }

    static func from(completedJourneyCount: Int) -> UserLevelProgress {
        let completed = max(0, completedJourneyCount)
        var level = 1
        var consumed = completed
        var required = journeysNeededToUpgrade(from: level)

        while consumed >= required {
            consumed -= required
            level += 1
            required = journeysNeededToUpgrade(from: level)
        }

        let safeRequired = max(1, required)
        let normalizedProgress = min(1, max(0, Double(consumed) / Double(safeRequired)))
        let remaining = max(0, safeRequired - consumed)

        return UserLevelProgress(
            completedJourneys: completed,
            level: level,
            journeysIntoCurrentLevel: consumed,
            journeysRequiredThisLevel: safeRequired,
            journeysRemainingToNextLevel: remaining,
            progress: normalizedProgress
        )
    }

    static func journeysNeededToUpgrade(from level: Int) -> Int {
        max(2, level + 1)
    }
}

struct LevelBadgeView: View {
    let level: Int

    var body: some View {
        Text(String(format: L10n.t("level_format"), level))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
    }
}
