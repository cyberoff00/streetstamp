import Foundation

enum JourneyVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`
    case friendsOnly
    case `public`

    var id: String { rawValue }

    @MainActor static var frontendCases: [JourneyVisibility] {
        FeatureFlagStore.shared.socialEnabled ? [.private, .friendsOnly] : [.private]
    }

    var localizedTitle: String {
        switch self {
        case .private: return L10n.t("visibility_private")
        case .friendsOnly: return L10n.t("visibility_friends_only")
        case .public: return L10n.t("visibility_public")
        }
    }
}

enum JourneyVisibilityPolicy {
    static let minFriendsVisibilityDistanceMeters: Double = 2_000

    enum DenialReason: Equatable {
        case loginRequired
        case journeyNotEligible

        var localizationKey: String {
            switch self {
            case .loginRequired:
                return "journey_visibility_login_required"
            case .journeyNotEligible:
                return "journey_visibility_requires_distance_or_memory"
            }
        }
    }

    struct Decision: Equatable {
        let isAllowed: Bool
        let reason: DenialReason?

        static let allowed = Decision(isAllowed: true, reason: nil)

        static func denied(_ reason: DenialReason) -> Decision {
            Decision(isAllowed: false, reason: reason)
        }
    }

    static func evaluateChange(
        current: JourneyVisibility,
        target: JourneyVisibility,
        isLoggedIn: Bool,
        journeyDistance: Double,
        memoryCount: Int
    ) -> Decision {
        guard current != target else { return .allowed }
        guard target == .friendsOnly else { return .allowed }
        guard isLoggedIn else { return .denied(.loginRequired) }
        guard journeyDistance >= minFriendsVisibilityDistanceMeters || memoryCount > 0 else {
            return .denied(.journeyNotEligible)
        }
        return .allowed
    }

    static func canEditVisibility(
        current: JourneyVisibility,
        target: JourneyVisibility,
        isLoggedIn: Bool
    ) -> Bool {
        guard isLoggedIn else { return false }
        return evaluateChange(
            current: current,
            target: target,
            isLoggedIn: isLoggedIn,
            journeyDistance: minFriendsVisibilityDistanceMeters,
            memoryCount: 1
        ).isAllowed
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
