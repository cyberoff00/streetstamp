import Foundation

enum PostcardInboxPresentation {
    struct DraftStatusPresentation: Equatable {
        let badgeText: String
        let detailText: String
        let showsRetry: Bool
    }

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

    static func avatarLoadout(
        for message: BackendPostcardMessageDTO,
        box: PostcardInboxView.Box,
        myUserID: String,
        myLoadout: RobotLoadout,
        friendLoadoutsByUserID: [String: RobotLoadout]
    ) -> RobotLoadout {
        if box == .sent {
            return myLoadout.normalizedForCurrentAvatar()
        }

        let trimmedMyUserID = myUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderUserID = message.fromUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMyUserID.isEmpty && senderUserID == trimmedMyUserID {
            return myLoadout.normalizedForCurrentAvatar()
        }
        if let senderLoadout = friendLoadoutsByUserID[senderUserID] {
            return senderLoadout.normalizedForCurrentAvatar()
        }
        return RobotLoadout.defaultBoy.normalizedForCurrentAvatar()
    }

    static func cardReaction(
        for message: BackendPostcardMessageDTO,
        box _: PostcardInboxView.Box
    ) -> PostcardReaction? {
        message.reaction
    }

    static func draftStatusPresentation(
        for status: PostcardDraftStatus,
        localize: (String) -> String = L10n.t
    ) -> DraftStatusPresentation? {
        switch status {
        case .draft:
            return nil
        case .sending:
            return DraftStatusPresentation(
                badgeText: localize("postcard_sending_status"),
                detailText: localize("postcard_send_queued_detail"),
                showsRetry: false
            )
        case .failed:
            return DraftStatusPresentation(
                badgeText: localize("postcard_failed_status"),
                detailText: localize("postcard_failed_retry_detail"),
                showsRetry: true
            )
        case .sent:
            let sent = localize("postcard_sent_status")
            return DraftStatusPresentation(
                badgeText: sent,
                detailText: sent,
                showsRetry: false
            )
        }
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
