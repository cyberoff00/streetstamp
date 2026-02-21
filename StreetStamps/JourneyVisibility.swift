import Foundation

enum JourneyVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case friendsOnly
    case `public`

    var id: String { rawValue }

    var titleCN: String {
        switch self {
        case .private: return "私密"
        case .friendsOnly: return "好友可见"
        case .public: return "公开"
        }
    }
}

enum ProfileVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case friendsOnly
    case `public`

    var id: String { rawValue }

    var titleCN: String {
        switch self {
        case .private: return "私密"
        case .friendsOnly: return "好友可见"
        case .public: return "公开"
        }
    }
}
