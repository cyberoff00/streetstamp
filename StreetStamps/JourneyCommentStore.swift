import Foundation
import Combine

/// Canonical local owner of journey-comment state for the active user.
///
/// Unlike `JourneyStore` / `LifelogStore` (local-first, cloud-secondary), this
/// store is cloud-first: the backend is the source of truth. Local state is
/// either freshly fetched or an optimistic insert pending confirmation.
@MainActor
final class JourneyCommentStore: ObservableObject {

    // MARK: - Published state

    /// Per-journey list of threads, owner-side; viewer-side has at most one.
    /// Sorted by the backend (unread first, then most-recent first).
    @Published private(set) var threadsByJourney: [String: [JourneyCommentThread]] = [:]

    /// Per-thread message lists, ordered ascending by `createdAt`.
    @Published private(set) var messagesByThread: [String: [JourneyComment]] = [:]

    /// Unread count per journey, used by the bubble badge.
    @Published private(set) var unreadCountByJourney: [String: Int] = [:]

    /// Aggregate unread across all journeys, for any global badge needs.
    @Published private(set) var totalUnreadCount: Int = 0

    /// Last error from a refresh / send / read call, for inline display.
    @Published private(set) var lastError: String?

    // MARK: - Internals

    private var activeUserID: String
    private let backend: JourneyCommentBackend
    private var loadingThreadsJourneys: Set<String> = []
    private var loadingMessagesThreads: Set<String> = []

    init(userID: String, backend: JourneyCommentBackend = MockJourneyCommentBackend.shared) {
        self.activeUserID = userID
        self.backend = backend
    }

    /// Called when the signed-in account changes. Resets all in-memory state.
    /// Empty `userID` represents sign-out / guest mode — state is cleared and
    /// the store stays inert until a real account ID arrives.
    func switchUser(_ userID: String) {
        guard userID != activeUserID else { return }
        activeUserID = userID
        threadsByJourney.removeAll()
        messagesByThread.removeAll()
        unreadCountByJourney.removeAll()
        totalUnreadCount = 0
        lastError = nil
    }

    // MARK: - Reads

    func unreadCount(forJourney journeyID: String) -> Int {
        unreadCountByJourney[journeyID] ?? 0
    }

    func threads(forJourney journeyID: String) -> [JourneyCommentThread] {
        threadsByJourney[journeyID] ?? []
    }

    func messages(forThread threadKey: String) -> [JourneyComment] {
        messagesByThread[threadKey] ?? []
    }

    // MARK: - Loading

    func refreshUnreadSummary(token: String?) async {
        do {
            let summary = try await backend.fetchUnreadSummary(viewerID: activeUserID, token: token)
            unreadCountByJourney = summary
            totalUnreadCount = summary.values.reduce(0, +)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadThreads(journeyID: String, token: String?) async {
        guard !loadingThreadsJourneys.contains(journeyID) else { return }
        loadingThreadsJourneys.insert(journeyID)
        defer { loadingThreadsJourneys.remove(journeyID) }
        do {
            let threads = try await backend.fetchThreads(
                journeyID: journeyID,
                viewerID: activeUserID,
                token: token
            )
            threadsByJourney[journeyID] = threads
            let count = threads.reduce(0) { $0 + $1.unreadCount }
            updateUnread(forJourney: journeyID, to: count)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadMessages(
        journeyID: String,
        otherUserID: String,
        token: String?,
        before: Date? = nil,
        limit: Int = 30
    ) async {
        let threadKey = JourneyCommentThreadKey.make(
            journeyID: journeyID,
            userA: activeUserID,
            userB: otherUserID
        )
        guard !loadingMessagesThreads.contains(threadKey) else { return }
        loadingMessagesThreads.insert(threadKey)
        defer { loadingMessagesThreads.remove(threadKey) }
        do {
            let page = try await backend.fetchMessages(
                journeyID: journeyID,
                otherUserID: otherUserID,
                viewerID: activeUserID,
                before: before,
                limit: limit,
                token: token
            )
            if before == nil {
                messagesByThread[threadKey] = page
            } else {
                let existing = messagesByThread[threadKey] ?? []
                // Page returns older messages; merge by id keeping ascending order.
                var merged = page
                let pageIDs = Set(page.map(\.id))
                merged.append(contentsOf: existing.filter { !pageIDs.contains($0.id) })
                merged.sort { $0.createdAt < $1.createdAt }
                messagesByThread[threadKey] = merged
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// Sends a comment from the active user. Returns the persisted comment on
    /// success, throws on failure. Caller is responsible for any UI retry.
    @discardableResult
    func send(
        journeyID: String,
        ownerID: String,
        recipientID: String,
        content: String,
        token: String?
    ) async throws -> JourneyComment {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JourneyCommentStoreError.emptyContent
        }
        let clipped = String(trimmed.prefix(JourneyCommentLimits.maxContentLength))
        let draftID = UUID().uuidString
        do {
            let comment = try await backend.send(
                journeyID: journeyID,
                ownerID: ownerID,
                recipientID: recipientID,
                senderID: activeUserID,
                content: clipped,
                clientDraftID: draftID,
                token: token
            )
            appendLocally(comment)
            lastError = nil
            return comment
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Marks all incoming messages in the (journeyID, otherUserID) thread as
    /// read. Optimistic locally, then confirmed by backend.
    func markRead(journeyID: String, otherUserID: String, token: String?) async {
        let threadKey = JourneyCommentThreadKey.make(
            journeyID: journeyID,
            userA: activeUserID,
            userB: otherUserID
        )
        var didMutate = false
        let now = Date()
        if var msgs = messagesByThread[threadKey] {
            for i in msgs.indices where msgs[i].recipientID == activeUserID && msgs[i].readAt == nil {
                msgs[i].readAt = now
                didMutate = true
            }
            if didMutate {
                messagesByThread[threadKey] = msgs
            }
        }
        if didMutate {
            recomputeUnread(forJourney: journeyID)
        }
        do {
            try await backend.markRead(
                journeyID: journeyID,
                otherUserID: otherUserID,
                viewerID: activeUserID,
                token: token
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

#if DEBUG
    /// Dev-only: injects a fake thread + mixed-direction messages directly into
    /// local state so the comment UI can be exercised without a second account
    /// or backend round-trips. `activeUserID` is treated as the owner side.
    func debugSeedFakeThread(journeyID: String, friendID: String, friendName: String) {
        let ownerID = activeUserID
        let threadKey = JourneyCommentThreadKey.make(journeyID: journeyID, userA: ownerID, userB: friendID)
        let base = Date().addingTimeInterval(-600)
        let msgs: [JourneyComment] = [
            JourneyComment(id: UUID().uuidString, journeyID: journeyID, ownerID: ownerID,
                           senderID: friendID, recipientID: ownerID, threadKey: threadKey,
                           content: "在哪拍的?", createdAt: base, readAt: nil, deletedAt: nil),
            JourneyComment(id: UUID().uuidString, journeyID: journeyID, ownerID: ownerID,
                           senderID: ownerID, recipientID: friendID, threadKey: threadKey,
                           content: "外滩 18 号外面那条小路", createdAt: base.addingTimeInterval(60),
                           readAt: Date(), deletedAt: nil),
            JourneyComment(id: UUID().uuidString, journeyID: journeyID, ownerID: ownerID,
                           senderID: friendID, recipientID: ownerID, threadKey: threadKey,
                           content: "哦哦看到了,周末一起去!", createdAt: base.addingTimeInterval(180),
                           readAt: nil, deletedAt: nil),
            JourneyComment(id: UUID().uuidString, journeyID: journeyID, ownerID: ownerID,
                           senderID: ownerID, recipientID: friendID, threadKey: threadKey,
                           content: "好啊 顺便吃顿饭", createdAt: base.addingTimeInterval(240),
                           readAt: Date(), deletedAt: nil),
        ]
        messagesByThread[threadKey] = msgs
        let thread = JourneyCommentThread(
            threadKey: threadKey, journeyID: journeyID, ownerID: ownerID,
            otherUserID: friendID, otherDisplayName: friendName, otherAvatarURL: nil,
            lastMessage: msgs.last, unreadCount: 1
        )
        threadsByJourney[journeyID] = [thread]
        updateUnread(forJourney: journeyID, to: 1)
    }
#endif

    func deleteComment(_ comment: JourneyComment, token: String?) async {
        guard comment.senderID == activeUserID else { return }
        let threadKey = comment.threadKey
        if var msgs = messagesByThread[threadKey] {
            msgs.removeAll { $0.id == comment.id }
            messagesByThread[threadKey] = msgs
        }
        do {
            try await backend.deleteComment(id: comment.id, viewerID: activeUserID, token: token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func appendLocally(_ comment: JourneyComment) {
        var msgs = messagesByThread[comment.threadKey] ?? []
        if !msgs.contains(where: { $0.id == comment.id }) {
            msgs.append(comment)
            msgs.sort { $0.createdAt < $1.createdAt }
            messagesByThread[comment.threadKey] = msgs
        }
        // The new message's thread may not be in threadsByJourney yet (e.g.
        // owner replies before threads list has been refreshed). The thread
        // summary list will refresh on next loadThreads call; UI typically
        // doesn't need the summary updated synchronously.
    }

    private func updateUnread(forJourney journeyID: String, to count: Int) {
        let previous = unreadCountByJourney[journeyID] ?? 0
        if count == 0 {
            unreadCountByJourney.removeValue(forKey: journeyID)
        } else {
            unreadCountByJourney[journeyID] = count
        }
        totalUnreadCount = max(0, totalUnreadCount - previous + count)
    }

    private func recomputeUnread(forJourney journeyID: String) {
        let threads = threadsByJourney[journeyID] ?? []
        // Thread summaries may be stale post-markRead; recompute from local
        // messages where available, falling back to thread counts.
        var count = 0
        for thread in threads {
            let msgs = messagesByThread[thread.threadKey]
            if let msgs {
                count += msgs.filter { $0.recipientID == activeUserID && $0.readAt == nil }.count
            } else {
                count += thread.unreadCount
            }
        }
        updateUnread(forJourney: journeyID, to: count)
    }
}

enum JourneyCommentStoreError: LocalizedError {
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .emptyContent: return "Comment is empty"
        }
    }
}
