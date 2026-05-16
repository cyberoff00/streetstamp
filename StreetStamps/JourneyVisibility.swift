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
    enum DenialReason: Equatable {
        case loginRequired

        var localizationKey: String {
            switch self {
            case .loginRequired:
                return "journey_visibility_login_required"
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

    /// `journeyDistance` and `hasMemory` are intentionally retained on the
    /// signature even though the policy no longer reads them, so existing
    /// call sites (SharingCard, JourneyMemoryNew) don't need to be touched.
    /// Quota enforcement (free-tier public-journey cap) now lives at the
    /// call site via `PublicJourneyQuota`, not here, because it needs the
    /// JourneyStore and membership tier — concerns this pure policy avoids.
    static func evaluateChange(
        current: JourneyVisibility,
        target: JourneyVisibility,
        isLoggedIn: Bool,
        journeyDistance: Double = 0,
        hasMemory: Bool = false
    ) -> Decision {
        _ = journeyDistance
        _ = hasMemory
        guard current != target else { return .allowed }
        guard target == .friendsOnly else { return .allowed }
        guard isLoggedIn else { return .denied(.loginRequired) }
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
            isLoggedIn: isLoggedIn
        ).isAllowed
    }
}

extension JourneyRoute {
    /// True if the journey has any user-authored memory content:
    /// per-point memories, overall-memory text, or overall-memory photos
    /// (local paths or remote URLs). Used by visibility gating so that
    /// adding only an overall memory still unlocks the friends toggle.
    var hasMemoryContent: Bool {
        if !memories.isEmpty { return true }
        if let text = overallMemory,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !overallMemoryImagePaths.isEmpty { return true }
        if !overallMemoryRemoteImageURLs.isEmpty { return true }
        return false
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
