import Foundation

enum SurfaceRefreshReminderPolicy {
    static let foregroundRefreshThreshold: TimeInterval = 30
    static let lightweightCheckCooldown: TimeInterval = 300
    static let promptCooldown: TimeInterval = 90

    static func shouldRunForegroundFreshnessCheck(lastBackgroundAt: Date?, now: Date) -> Bool {
        guard let lastBackgroundAt else { return false }
        return now.timeIntervalSince(lastBackgroundAt) >= foregroundRefreshThreshold
    }

    static func shouldRunLightweightCheck(lastCheckedAt: Date?, now: Date) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= lightweightCheckCooldown
    }

    static func shouldShowPrompt(lastPromptAt: Date?, now: Date) -> Bool {
        guard let lastPromptAt else { return true }
        return now.timeIntervalSince(lastPromptAt) >= promptCooldown
    }
}
