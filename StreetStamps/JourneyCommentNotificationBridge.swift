import Foundation

extension Notification.Name {
    /// Posted when an APNs push for `type == "journey_comment"` arrives. The
    /// userInfo carries the `d` payload from the push (`journeyID`,
    /// `senderID`, `ownerID`). Listeners on `@MainActor` (e.g.
    /// `JourneyCommentStore`) react by refreshing the affected journey's
    /// unread state.
    static let journeyCommentReceivedPush = Notification.Name("journeyCommentReceivedPush")
}

/// Target of an APNs tap on a journey-comment notification. The user wants to
/// land on the journey detail with the comment thread open.
struct JourneyCommentDeepLink: Equatable, Hashable, Identifiable {
    let journeyID: String
    let ownerID: String
    /// Sender of the comment that fired the push. Useful on the owner side so
    /// the multi-block sheet can scroll the right friend's block to the top.
    let senderID: String?

    var id: String { "\(journeyID)|\(ownerID)|\(senderID ?? "")" }
}

enum JourneyCommentNotificationBridge {
    /// Returns true if the incoming APNs userInfo represents a journey comment
    /// notification. On a match, posts `.journeyCommentReceivedPush` with the
    /// payload so the in-app store can refresh.
    @discardableResult
    static func handleIncomingPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let data = extractDataPayload(userInfo),
              (data["type"] as? String) == "journey_comment" else {
            return false
        }
        var forwarded: [AnyHashable: Any] = [:]
        for (key, value) in data { forwarded[key] = value }
        NotificationCenter.default.post(
            name: .journeyCommentReceivedPush,
            object: nil,
            userInfo: forwarded
        )
        return true
    }

    /// Parses an APNs payload into a deep-link target. Returns nil if the
    /// payload is not a journey-comment push or is missing required fields.
    static func deepLink(from userInfo: [AnyHashable: Any]) -> JourneyCommentDeepLink? {
        guard let data = extractDataPayload(userInfo),
              (data["type"] as? String) == "journey_comment" else {
            return nil
        }
        let journeyID = (data["journeyID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ownerID = (data["ownerID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !journeyID.isEmpty, !ownerID.isEmpty else { return nil }
        let rawSender = (data["senderID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let senderID = rawSender.isEmpty ? nil : rawSender
        return JourneyCommentDeepLink(journeyID: journeyID, ownerID: ownerID, senderID: senderID)
    }

    /// APNs custom data may arrive nested under `"d"` (our convention) or
    /// flattened at the top level (some test tools do this). Accept both.
    static func extractDataPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
        if let nested = userInfo["d"] as? [String: Any] {
            return nested
        }
        if let typed = userInfo["type"] as? String, !typed.isEmpty {
            var flattened: [String: Any] = [:]
            for (key, value) in userInfo {
                if let k = key as? String { flattened[k] = value }
            }
            return flattened
        }
        return nil
    }
}

/// Tap target of a non-comment social APNs push (`d.type` payloads added by
/// the backend for every notification type). Routing mirrors the in-app
/// notification inbox rows in FriendsHubView.
enum SocialPushDeepLink: Equatable {
    case myJourney(journeyID: String)
    case friendProfile(friendID: String)
    case friendRequests
    case postcardInbox(box: String, messageID: String?)

    static func parse(from userInfo: [AnyHashable: Any]) -> SocialPushDeepLink? {
        guard let data = JourneyCommentNotificationBridge.extractDataPayload(userInfo),
              let type = data["type"] as? String else { return nil }
        func field(_ key: String) -> String? {
            let value = (data[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        switch type {
        case "journey_like":
            guard let journeyID = field("journeyID") else { return nil }
            return .myJourney(journeyID: journeyID)
        case "profile_stomp":
            guard let friendID = field("fromUserID") else { return nil }
            return .friendProfile(friendID: friendID)
        case "friend_request":
            return .friendRequests
        case "friend_request_accepted":
            // Inbox parity: the accepted row navigates to the new friend's
            // profile; without a sender it still lands on the friends list.
            guard let friendID = field("fromUserID") else { return .friendRequests }
            return .friendProfile(friendID: friendID)
        case "postcard_received":
            return .postcardInbox(box: "received", messageID: field("messageID"))
        case "postcard_reaction":
            return .postcardInbox(box: "sent", messageID: field("messageID"))
        default:
            return nil
        }
    }

    /// Remote postcard pushes carry the inbox notification ID so the local
    /// fallback banner for the same postcard can be suppressed.
    static func remotePostcardNotifID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let data = JourneyCommentNotificationBridge.extractDataPayload(userInfo),
              (data["type"] as? String) == "postcard_received" else { return nil }
        let raw = (data["notifID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }
}
