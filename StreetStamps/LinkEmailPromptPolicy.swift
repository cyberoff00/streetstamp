import Foundation

enum LinkEmailPromptPolicy {
    private static let dismissedAtKey = "streetstamps.link_email_prompt.dismissed_at"
    private static let cooldownInterval: TimeInterval = 3 * 24 * 60 * 60 // 3 days

    static func shouldShow() -> Bool {
        guard let dismissedAt = UserDefaults.standard.object(forKey: dismissedAtKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(dismissedAt) >= cooldownInterval
    }

    static func recordDismissal() {
        UserDefaults.standard.set(Date(), forKey: dismissedAtKey)
    }
}
