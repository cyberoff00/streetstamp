import Foundation

enum SocialNotificationPresentation {
    static func badgeTitle(for item: BackendNotificationItem, locale: Locale = .current) -> String {
        L10n.t(badgeTitleKey(for: item), locale: locale)
    }

    static func message(for item: BackendNotificationItem, locale: Locale = .current) -> String {
        switch item.type {
        case "journey_like":
            guard
                let displayName = normalized(item.fromDisplayName),
                let journeyTitle = normalized(item.journeyTitle)
            else {
                return item.message
            }
            return String(
                format: L10n.t("notification_journey_like_format", locale: locale),
                locale: locale,
                displayName,
                journeyTitle
            )

        case "profile_stomp":
            guard let displayName = normalized(item.fromDisplayName) else {
                return item.message
            }
            return String(format: L10n.t("notification_profile_stomp_format", locale: locale), locale: locale, displayName)

        case "friend_request":
            if let displayName = normalized(item.fromDisplayName) {
                return String(format: L10n.t("notification_friend_request_format", locale: locale), locale: locale, displayName)
            }
            return L10n.t("notification_friend_request_fallback", locale: locale)

        case "friend_request_accepted":
            guard let displayName = normalized(item.fromDisplayName) else {
                return item.message
            }
            return String(
                format: L10n.t("notification_friend_request_accepted_format", locale: locale),
                locale: locale,
                displayName
            )

        case "postcard_reaction":
            return item.message

        default:
            return item.message
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func badgeTitleKey(for item: BackendNotificationItem) -> String {
        switch item.type {
        case "postcard_received":
            return "postcard_notification_badge"
        case "postcard_reaction":
            return "postcard_notification_badge"
        case "journey_like":
            return "social_notice_like"
        case "friend_request":
            return "social_notice_friend_request"
        case "friend_request_accepted":
            return "social_notice_friend_update"
        default:
            return "social_notice_stomp"
        }
    }
}
