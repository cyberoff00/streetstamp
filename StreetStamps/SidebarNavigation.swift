import SwiftUI

// MARK: - Navigation Tabs Enum

enum NavigationTab: Int, CaseIterable, Identifiable {
    case start = 0
    case cities = 1
    case friends = 2
    case memory = 3
    case profile = 4
    case lifelog = 5
    case settings = 7

    var id: Int { rawValue }

    static var allCases: [NavigationTab] {
        [.start, .memory, .cities, .friends, .lifelog, .profile, .settings]
    }

    var title: String {
        switch self {
        case .start: return "START"
        case .cities: return "CITIES"
        case .friends: return "FRIENDS"
        case .memory: return "MEMORY"
        case .lifelog: return "LIFELOG"
        case .profile: return "PROFILE"
        case .settings: return "SETTINGS"
        }
    }

    var icon: String {
        switch self {
        case .start: return "house"
        case .cities: return "mappin.and.ellipse"
        case .friends: return "person.2"
        case .memory: return "heart"
        case .lifelog: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }
}
