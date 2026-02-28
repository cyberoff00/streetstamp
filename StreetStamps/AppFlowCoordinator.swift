import Foundation
import Combine

/// App-level flow triggers that should not be tied to any single tab/view lifecycle.
///
/// Why signals?
/// - A Bool can be missed if a view is not currently observing when it flips.
/// - An incrementing Int is a simple, reliable "edge trigger".
@MainActor
final class AppFlowCoordinator: ObservableObject {
    @Published private(set) var resumeOngoingSignal: Int = 0
    @Published private(set) var endOngoingSignal: Int = 0
    @Published private(set) var sidebarHiddenTokens: Set<String> = []
    @Published private(set) var requestedTab: NavigationTab?

    func requestResumeOngoing() {
        resumeOngoingSignal += 1
    }

    func requestEndOngoing() {
        endOngoingSignal += 1
    }

    func requestSelectTab(_ tab: NavigationTab) {
        requestedTab = tab
    }

    func clearRequestedTab() {
        requestedTab = nil
    }

    var shouldShowSidebarButton: Bool {
        sidebarHiddenTokens.isEmpty
    }

    func pushSidebarButtonHidden(token: String) {
        guard !token.isEmpty else { return }
        sidebarHiddenTokens.insert(token)
    }

    func popSidebarButtonHidden(token: String) {
        guard !token.isEmpty else { return }
        sidebarHiddenTokens.remove(token)
    }
}

struct FriendInviteIntent: Equatable {
    var inviteCode: String?
    var handle: String?

    var isEmpty: Bool {
        (inviteCode?.isEmpty ?? true) && (handle?.isEmpty ?? true)
    }
}

@MainActor
final class AppDeepLinkStore: ObservableObject {
    @Published private(set) var pendingFriendInvite: FriendInviteIntent?

    func handleIncomingURL(_ url: URL) -> FriendInviteIntent? {
        guard let intent = Self.parseInvite(from: url) else { return nil }
        guard !intent.isEmpty else { return nil }
        pendingFriendInvite = intent
        return intent
    }

    func consumePendingFriendInvite() {
        pendingFriendInvite = nil
    }

    static func parseInvite(from rawText: String) -> FriendInviteIntent? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let parsed = parseInvite(from: url), !parsed.isEmpty {
            return parsed
        }

        let normalized = trimmed.uppercased()
        if normalized.range(of: #"^[A-Z0-9]{8}$"#, options: .regularExpression) != nil {
            return FriendInviteIntent(inviteCode: normalized, handle: nil)
        }

        let normalizedHandle = Self.normalizedHandle(trimmed)
        if let normalizedHandle,
           normalizedHandle.range(of: #"^[a-z0-9_]{1,24}$"#, options: .regularExpression) != nil {
            return FriendInviteIntent(inviteCode: nil, handle: normalizedHandle)
        }
        return nil
    }

    static func parseInvite(from url: URL) -> FriendInviteIntent? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }

        let scheme = (components.scheme ?? "").lowercased()
        if !(scheme == "streetstamps" || scheme == "https" || scheme == "http") {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let inviteCode = normalizedCode(
            firstNonEmptyValue(in: queryItems, keys: ["code", "inviteCode", "invite", "i"])
        )
        let handle = normalizedHandle(
            firstNonEmptyValue(in: queryItems, keys: ["handle", "exclusiveID", "id", "h"])
        )

        if inviteCode != nil || handle != nil {
            return FriendInviteIntent(inviteCode: inviteCode, handle: handle)
        }

        return nil
    }

    private static func firstNonEmptyValue(in queryItems: [URLQueryItem], keys: [String]) -> String? {
        for key in keys {
            if let value = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func normalizedCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.isEmpty { return nil }
        return value
    }

    private static func normalizedHandle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("@") {
            value.removeFirst()
        }
        if value.isEmpty { return nil }
        return value
    }
}
