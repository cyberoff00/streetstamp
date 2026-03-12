import Foundation

enum PostcardInboxPresentation {
    static func recipientLabel(
        toDisplayName: String?,
        toUserID: String,
        fallbackDisplayName: String? = nil,
        localize: (String) -> String = L10n.t
    ) -> String {
        resolvedLabel(
            primaryDisplayName: toDisplayName,
            fallbackDisplayName: fallbackDisplayName,
            userID: toUserID,
            localize: localize
        )
    }

    static func senderLabel(
        fromDisplayName: String?,
        fromUserID: String,
        fallbackDisplayName: String? = nil,
        localize: (String) -> String = L10n.t
    ) -> String {
        resolvedLabel(
            primaryDisplayName: fromDisplayName,
            fallbackDisplayName: fallbackDisplayName,
            userID: fromUserID,
            localize: localize
        )
    }

    static func viewIdentity(initialBox: PostcardInboxView.Box, focusMessageID: String?) -> String {
        let focus = focusMessageID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(initialBox.rawValue)|\(focus)"
    }

    private static func resolvedLabel(
        primaryDisplayName: String?,
        fallbackDisplayName: String?,
        userID: String,
        localize: (String) -> String
    ) -> String {
        if let displayName = normalizedDisplayName(primaryDisplayName) {
            return displayName
        }
        if let fallbackDisplayName = normalizedDisplayName(fallbackDisplayName) {
            return fallbackDisplayName
        }

        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else {
            return localize("unknown")
        }
        if looksLikeInternalUserID(trimmedUserID) {
            return localize("unknown")
        }
        return trimmedUserID
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func looksLikeInternalUserID(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasPrefix("u_") || lowercased.hasPrefix("account_")
    }
}
