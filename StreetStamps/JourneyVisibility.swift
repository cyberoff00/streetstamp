import Foundation

enum JourneyVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case friendsOnly
    case `public`

    var id: String { rawValue }

    static var frontendCases: [JourneyVisibility] {
        [.private, .friendsOnly]
    }

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

    static var frontendCases: [ProfileVisibility] {
        [.private, .friendsOnly]
    }

    var titleCN: String {
        switch self {
        case .private: return "私密"
        case .friendsOnly: return "好友可见"
        case .public: return "公开"
        }
    }
}
