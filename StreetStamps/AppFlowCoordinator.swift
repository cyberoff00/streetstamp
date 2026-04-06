import Foundation
import Combine

enum PostcardSidebarVisibilityScope {
    case composer
    case preview

    var hidesGlobalSidebarButton: Bool {
        true
    }

    var token: String {
        switch self {
        case .composer:
            return "postcard-composer"
        case .preview:
            return "postcard-preview"
        }
    }
}

/// App-level flow triggers that should not be tied to any single tab/view lifecycle.
///
/// Why signals?
/// - A Bool can be missed if a view is not currently observing when it flips.
/// - An incrementing Int is a simple, reliable "edge trigger".
@MainActor
final class AppFlowCoordinator: ObservableObject {
    static let shared = AppFlowCoordinator()

    @Published private(set) var resumeOngoingSignal: Int = 0
    @Published private(set) var endOngoingSignal: Int = 0
    @Published private(set) var pendingWidgetCaptureSignal: Int = 0
    @Published private(set) var openPostcardSidebarSignal: Int = 0
    @Published private(set) var openModalDestinationSignal: Int = 0
    @Published private(set) var pendingPostcardSidebarIntent: PostcardInboxIntent?
    @Published private(set) var pendingModalDestination: ModalNavDestination?
    @Published private(set) var sidebarHiddenTokens: Set<String> = []
    @Published private(set) var requestedTab: NavigationTab?
    @Published private(set) var requestedCollectionPage: Int?
    @Published private(set) var currentTab: NavigationTab = .start

    func requestResumeOngoing() {
        resumeOngoingSignal += 1
    }

    func requestEndOngoing() {
        endOngoingSignal += 1
    }

    func requestWidgetCapture() {
        pendingWidgetCaptureSignal += 1
    }

    func consumeWidgetCapture() {
        pendingWidgetCaptureSignal = 0
    }

    func requestOpenPostcardSidebar(_ intent: PostcardInboxIntent) {
        pendingPostcardSidebarIntent = intent
        openPostcardSidebarSignal += 1
    }

    func requestModalPush(_ destination: ModalNavDestination) {
        pendingModalDestination = destination
        openModalDestinationSignal += 1
    }

    func consumePendingPostcardSidebarIntent() {
        pendingPostcardSidebarIntent = nil
    }

    func consumePendingModalDestination() {
        pendingModalDestination = nil
    }

    func requestSelectTab(_ tab: NavigationTab) {
        requestedTab = tab
    }

    func clearRequestedTab() {
        requestedTab = nil
    }

    func requestSelectCollectionPage(_ rawPage: Int) {
        requestedCollectionPage = rawPage
    }

    func clearRequestedCollectionPage() {
        requestedCollectionPage = nil
    }

    func updateCurrentTab(_ tab: NavigationTab) {
        currentTab = tab
    }

    var shouldShowSidebarButton: Bool {
        sidebarHiddenTokens.isEmpty
    }

    func pushSidebarButtonHidden(token: String) {
        guard !token.isEmpty, !sidebarHiddenTokens.contains(token) else { return }
        sidebarHiddenTokens.insert(token)
    }

    func popSidebarButtonHidden(token: String) {
        guard !token.isEmpty, sidebarHiddenTokens.contains(token) else { return }
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

struct PostcardInboxIntent: Equatable {
    var box: String
    var messageID: String?
}

@MainActor
final class AppDeepLinkStore: ObservableObject {
    @Published private(set) var pendingFriendInvite: FriendInviteIntent?
    @Published private(set) var pendingPostcardInbox: PostcardInboxIntent?
    @Published private(set) var pendingPasswordResetToken: String?

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        if let resetToken = Self.parsePasswordResetToken(from: url) {
            pendingPasswordResetToken = resetToken
            return true
        }
        if let inviteIntent = Self.parseInvite(from: url), !inviteIntent.isEmpty {
            pendingFriendInvite = inviteIntent
            return true
        }
        if let postcardIntent = Self.parsePostcardInbox(from: url) {
            pendingPostcardInbox = postcardIntent
            return true
        }
        return false
    }

    func consumePendingFriendInvite() {
        pendingFriendInvite = nil
    }

    func consumePendingPostcardInbox() {
        pendingPostcardInbox = nil
    }

    func consumePendingPasswordResetToken() {
        pendingPasswordResetToken = nil
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

    static func parsePostcardInbox(from url: URL) -> PostcardInboxIntent? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        let scheme = (components.scheme ?? "").lowercased()
        guard scheme == "streetstamps" || scheme == "https" || scheme == "http" else { return nil }

        let host = (components.host ?? "").lowercased()
        guard host == "postcards" || host == "postcard" else { return nil }

        let queryItems = components.queryItems ?? []
        let rawBox = firstNonEmptyValue(in: queryItems, keys: ["box"])?.lowercased() ?? "received"
        let box = rawBox == "sent" ? "sent" : "received"
        let messageID = firstNonEmptyValue(in: queryItems, keys: ["messageID", "messageId", "mid"])
        return PostcardInboxIntent(box: box, messageID: messageID)
    }

    private static func parsePasswordResetToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        let scheme = (components.scheme ?? "").lowercased()
        guard scheme == "streetstamps" else { return nil }

        let host = (components.host ?? "").lowercased()
        guard host == "reset-password" else { return nil }

        return firstNonEmptyValue(in: components.queryItems ?? [], keys: ["token"])
    }
}
