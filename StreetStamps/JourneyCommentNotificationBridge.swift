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
    private static func extractDataPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
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
