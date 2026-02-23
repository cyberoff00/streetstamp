import Foundation

enum ProfileSharingSettings {
    private static let profileVisibilityKey = "streetstamps.profile.visibility"

    static var visibility: ProfileVisibility {
        get {
            let raw = UserDefaults.standard.string(forKey: profileVisibilityKey) ?? "friendsOnly"
            return ProfileVisibility(rawValue: raw) ?? .friendsOnly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: profileVisibilityKey)
        }
    }

    static func normalizeHandle(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        return String(cleaned.prefix(24))
    }

    static func handle(for source: String) -> String {
        let normalized = normalizeHandle(source)
        if normalized.isEmpty { return "00000000" }
        return normalized
    }
}
