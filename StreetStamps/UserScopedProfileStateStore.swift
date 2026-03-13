import Foundation

enum UserScopedProfileStateStore {
    static let globalDisplayNameKey = "streetstamps.profile.displayName"
    static let globalAvatarLoadoutKey = "avatar.loadout.v2"

    static func displayNameKey(for userID: String) -> String {
        "streetstamps.profile.displayName.user.\(userID)"
    }

    static func avatarLoadoutKey(for userID: String) -> String {
        "avatar.loadout.v2.user.\(userID)"
    }

    static func pendingAvatarLoadoutKey(for userID: String) -> String {
        "avatar.loadout.v2.pending.user.\(userID)"
    }

    static func pendingProfileSetupKey(for userID: String) -> String {
        "streetstamps.profile.setup.pending.user.\(userID)"
    }

    static func initializeCurrentUser(_ userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }

        captureCurrentGlobalStateIfPresent(for: userID, defaults: defaults)
        restoreGlobalState(for: userID, defaults: defaults)
    }

    static func switchActiveUser(from previousUserID: String, to nextUserID: String, defaults: UserDefaults = .standard) {
        guard !nextUserID.isEmpty else { return }

        if !previousUserID.isEmpty {
            persistCurrentGlobalState(for: previousUserID, defaults: defaults)
        }
        restoreGlobalState(for: nextUserID, defaults: defaults)
    }

    static func saveCurrentLoadout(_ loadout: RobotLoadout, for userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }
        guard let data = normalizedLoadoutData(loadout) else { return }

        defaults.set(data, forKey: globalAvatarLoadoutKey)
        defaults.set(data, forKey: avatarLoadoutKey(for: userID))
    }

    static func markPendingLoadout(_ loadout: RobotLoadout, for userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }
        guard let data = normalizedLoadoutData(loadout) else { return }

        defaults.set(data, forKey: pendingAvatarLoadoutKey(for: userID))
    }

    static func pendingLoadout(for userID: String, defaults: UserDefaults = .standard) -> RobotLoadout? {
        guard !userID.isEmpty else { return nil }
        guard let data = defaults.data(forKey: pendingAvatarLoadoutKey(for: userID)) else { return nil }
        return normalizedLoadout(from: data)
    }

    static func clearPendingLoadout(for userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }
        defaults.removeObject(forKey: pendingAvatarLoadoutKey(for: userID))
    }

    static func markProfileSetupPending(for userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }
        defaults.set(true, forKey: pendingProfileSetupKey(for: userID))
    }

    static func isProfileSetupPending(for userID: String, defaults: UserDefaults = .standard) -> Bool {
        guard !userID.isEmpty else { return false }
        return defaults.bool(forKey: pendingProfileSetupKey(for: userID))
    }

    static func clearProfileSetupPending(for userID: String, defaults: UserDefaults = .standard) {
        guard !userID.isEmpty else { return }
        defaults.removeObject(forKey: pendingProfileSetupKey(for: userID))
    }

    private static func captureCurrentGlobalStateIfPresent(for userID: String, defaults: UserDefaults) {
        let userDisplayNameKey = displayNameKey(for: userID)
        if let globalDisplayName = defaults.string(forKey: globalDisplayNameKey) {
            defaults.set(globalDisplayName, forKey: userDisplayNameKey)
        }

        let userLoadoutKey = avatarLoadoutKey(for: userID)
        if let globalLoadoutData = defaults.data(forKey: globalAvatarLoadoutKey),
           let normalized = normalizedLoadoutData(globalLoadoutData) {
            defaults.set(normalized, forKey: userLoadoutKey)
        }
    }

    private static func persistCurrentGlobalState(for userID: String, defaults: UserDefaults) {
        let userDisplayNameKey = displayNameKey(for: userID)
        if let globalDisplayName = defaults.string(forKey: globalDisplayNameKey) {
            defaults.set(globalDisplayName, forKey: userDisplayNameKey)
        } else {
            defaults.removeObject(forKey: userDisplayNameKey)
        }

        let userLoadoutKey = avatarLoadoutKey(for: userID)
        if let globalLoadoutData = defaults.data(forKey: globalAvatarLoadoutKey),
           let normalized = normalizedLoadoutData(globalLoadoutData) {
            defaults.set(normalized, forKey: userLoadoutKey)
        } else {
            defaults.removeObject(forKey: userLoadoutKey)
        }
    }

    private static func restoreGlobalState(for userID: String, defaults: UserDefaults) {
        let userDisplayNameKey = displayNameKey(for: userID)
        if let scopedDisplayName = defaults.string(forKey: userDisplayNameKey) {
            defaults.set(scopedDisplayName, forKey: globalDisplayNameKey)
        } else {
            defaults.removeObject(forKey: globalDisplayNameKey)
        }

        let userLoadoutKey = avatarLoadoutKey(for: userID)
        if let scopedLoadoutData = defaults.data(forKey: userLoadoutKey),
           let normalized = normalizedLoadoutData(scopedLoadoutData) {
            defaults.set(normalized, forKey: globalAvatarLoadoutKey)
        } else {
            defaults.removeObject(forKey: globalAvatarLoadoutKey)
        }
    }

    private static func normalizedLoadoutData(_ data: Data) -> Data? {
        guard let decoded = normalizedLoadout(from: data) else { return nil }
        return try? JSONEncoder().encode(decoded)
    }

    private static func normalizedLoadoutData(_ loadout: RobotLoadout) -> Data? {
        try? JSONEncoder().encode(loadout.normalizedForCurrentAvatar())
    }

    private static func normalizedLoadout(from data: Data) -> RobotLoadout? {
        guard let decoded = try? JSONDecoder().decode(RobotLoadout.self, from: data) else {
            return nil
        }
        return decoded.normalizedForCurrentAvatar()
    }
}
