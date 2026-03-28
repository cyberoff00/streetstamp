import Foundation

enum AppSettings {
    static let voiceBroadcastEnabledKey = "streetstamps.voice.broadcast.enabled"
    static let voiceBroadcastIntervalKMKey = "streetstamps.voice.broadcast.interval_km"
    static let longStationaryReminderEnabledKey = "streetstamps.long_stationary_reminder.enabled"
    static let liveActivityEnabledKey = "streetstamps.live_activity.enabled"
    static let dailyTrackingPrecisionKey = "streetstamps.daily.tracking.precision"
    static let lifelogPassiveEnabledKey = "streetstamps.lifelog.passive.enabled"
    static let iCloudSyncEnabledKey = "streetstamps.icloud.sync.enabled"
    static let iCloudAutomaticRestoreEnabledKey = "streetstamps.icloud.sync.auto_restore.enabled"

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

    static var isLiveActivityEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: liveActivityEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: liveActivityEnabledKey)
    }

    static var dailyTrackingPrecision: DailyTrackingPrecision {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: dailyTrackingPrecisionKey),
              let precision = DailyTrackingPrecision(rawValue: raw) else {
            return .defaultPrecision
        }
        return precision
    }

    static var hasPassiveLifelogPreference: Bool {
        UserDefaults.standard.object(forKey: lifelogPassiveEnabledKey) != nil
    }

    static var isPassiveLifelogEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lifelogPassiveEnabledKey) == nil {
            return false
        }
        return defaults.bool(forKey: lifelogPassiveEnabledKey)
    }

    static func setPassiveLifelogEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: lifelogPassiveEnabledKey)
    }

    static var isICloudSyncEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: iCloudSyncEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: iCloudSyncEnabledKey)
    }

    static var isAutomaticICloudRestoreEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: iCloudAutomaticRestoreEnabledKey) == nil {
            return false
        }
        return defaults.bool(forKey: iCloudAutomaticRestoreEnabledKey)
    }
}
