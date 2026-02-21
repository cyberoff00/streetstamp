import Foundation

enum AppSettings {
    static let voiceBroadcastEnabledKey = "streetstamps.voice.broadcast.enabled"
    static let voiceBroadcastIntervalKMKey = "streetstamps.voice.broadcast.interval_km"
    static let longStationaryReminderEnabledKey = "streetstamps.long_stationary_reminder.enabled"
    static let avatarHeadlightEnabledKey = "streetstamps.avatar.headlight.enabled"

    static var isVoiceBroadcastEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: voiceBroadcastEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: voiceBroadcastEnabledKey)
    }

    static var voiceBroadcastIntervalKM: Int {
        let raw = UserDefaults.standard.integer(forKey: voiceBroadcastIntervalKMKey)
        return [1, 2, 5].contains(raw) ? raw : 1
    }

    static var isLongStationaryReminderEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: longStationaryReminderEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: longStationaryReminderEnabledKey)
    }

    static var isAvatarHeadlightEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: avatarHeadlightEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: avatarHeadlightEnabledKey)
    }
}
