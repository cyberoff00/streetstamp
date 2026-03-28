import Foundation

/// Controls the precision/battery tradeoff for daily journey tracking.
/// High precision uses better background GPS; low precision prioritizes battery.
enum DailyTrackingPrecision: String, CaseIterable {
    case highPrecision
    case lowPrecision

    static let defaultPrecision: DailyTrackingPrecision = .lowPrecision

    var titleKey: String {
        switch self {
        case .highPrecision: return "settings_daily_precision_high"
        case .lowPrecision: return "settings_daily_precision_low"
        }
    }
}
