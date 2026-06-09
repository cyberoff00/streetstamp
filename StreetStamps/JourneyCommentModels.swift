import Foundation

/// A single comment in a 1-on-1 thread anchored to a journey.
///
/// Threads are always viewer-initiated: a friend who views the owner's journey
/// opens a thread by posting the first comment. Both sides may then exchange
/// messages within that thread. The owner cannot create a thread proactively.
struct JourneyComment: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let journeyID: String
    let ownerID: String
    let senderID: String
    let recipientID: String
    let threadKey: String
    let content: String
    let createdAt: Date
    var readAt: Date?
    var deletedAt: Date?

    /// Client-only optimistic-send lifecycle. NEVER crosses the wire — excluded
    /// from `CodingKeys`, so anything decoded from the backend (or encoded) is
    /// always `.sent`. Only locally-inserted optimistic messages carry
    /// `.sending` / `.failed`.
    var sendState: CommentSendState = .sent
    /// Client draft id of the optimistic insert, used to reconcile the local
    /// bubble with the server-confirmed comment. nil once confirmed / for
    /// fetched messages.
    var clientDraftID: String? = nil

    var isDeleted: Bool { deletedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, journeyID, ownerID, senderID, recipientID, threadKey, content
        case createdAt, readAt, deletedAt
    }
}

/// Optimistic-send state for a locally-composed comment.
enum CommentSendState: Sendable, Equatable, Hashable {
    /// Confirmed by the backend, or freshly fetched. The only state on the wire.
    case sent
    /// Optimistically inserted, network round-trip in flight.
    case sending
    /// Send failed; the bubble offers a retry affordance.
    case failed
}

/// Summary of a single thread shown on the owner's multi-block screen, or
/// (with `otherUserID == ownerID`) the viewer's single-block screen.
struct JourneyCommentThread: Identifiable, Equatable, Hashable, Sendable {
    let threadKey: String
    let journeyID: String
    let ownerID: String
    /// The conversation partner from the viewing user's perspective.
    /// - Owner viewing: this is the friend who started the thread.
    /// - Viewer (friend) viewing: this is the owner.
    let otherUserID: String
    let otherDisplayName: String?
    let otherAvatarURL: String?
    let lastMessage: JourneyComment?
    let unreadCount: Int

    var id: String { threadKey }
}

/// Canonical thread key for a (journey, userA, userB) triple. The pair is
/// sorted so both endpoints compute the same key regardless of role.
enum JourneyCommentThreadKey {
    static func make(journeyID: String, userA: String, userB: String) -> String {
        let pair = [userA, userB].sorted()
        return "\(journeyID):\(pair[0]):\(pair[1])"
    }
}

enum JourneyCommentLimits {
    static let maxContentLength = 300
}

// MARK: - Backend DTOs

struct BackendJourneyCommentThreadDTO: Codable, Sendable {
    let threadKey: String
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let unreadCount: Int
    let lastMessage: JourneyComment?
}

struct BackendJourneyCommentThreadsResponse: Codable, Sendable {
    let threads: [BackendJourneyCommentThreadDTO]
}

struct BackendJourneyCommentMessagesResponse: Codable, Sendable {
    let messages: [JourneyComment]
}

struct BackendSendJourneyCommentRequest: Codable, Sendable {
    let ownerID: String
    let recipientID: String
    let content: String
    let clientDraftID: String
}

struct BackendSendJourneyCommentResponse: Codable, Sendable {
    let comment: JourneyComment
    let idempotent: Bool?
}

struct BackendJourneyCommentUnreadSummaryResponse: Codable, Sendable {
    let summary: [String: Int]
}

struct BackendJourneyCommentMarkReadRequest: Codable, Sendable {
    let withUserID: String
}
