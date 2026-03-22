import Foundation

enum LifelogBackgroundMode: String, CaseIterable {
    case highPrecision
    case lowPrecision

    static let defaultMode: LifelogBackgroundMode = .highPrecision

    var titleKey: String {
        switch self {
        case .highPrecision: return "settings_lifelog_bg_mode_high"
        case .lowPrecision: return "settings_lifelog_bg_mode_low"
        }
    }
}
