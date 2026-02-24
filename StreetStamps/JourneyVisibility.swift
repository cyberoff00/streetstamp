import Foundation

enum JourneyVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case friendsOnly
    case `public`

    var id: String { rawValue }

    static var frontendCases: [JourneyVisibility] {
        [.private, .friendsOnly]
    }

    var localizedTitle: String {
        switch self {
        case .private: return L10n.t("visibility_private")
        case .friendsOnly: return L10n.t("visibility_friends_only")
        case .public: return L10n.t("visibility_public")
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

    var localizedTitle: String {
        switch self {
        case .private: return L10n.t("visibility_private")
        case .friendsOnly: return L10n.t("visibility_friends_only")
        case .public: return L10n.t("visibility_public")
        }
    }
}
