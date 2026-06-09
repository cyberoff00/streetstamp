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

    /// Initial-load phase per thread, so the UI can tell "still loading" and
    /// "load failed" apart from "genuinely no messages" (all three otherwise
    /// render as an empty message list).
    @Published private(set) var messageLoadPhaseByThread: [String: ThreadLoadPhase] = [:]

    /// Initial-load phase for a journey's owner-side thread list, same purpose.
    @Published private(set) var threadsLoadPhaseByJourney: [String: ThreadLoadPhase] = [:]

    /// Whether an older page may still exist for a thread, so the UI can show a
    /// "load earlier" affordance. Set after every message fetch from whether the
    /// page came back full.
    @Published private(set) var hasMoreOlderByThread: [String: Bool] = [:]

    /// Whether an older-page fetch is currently in flight, for the load-earlier
    /// spinner. Distinct from the initial-load phase, which pagination never
    /// touches.
    @Published private(set) var loadingOlderByThread: [String: Bool] = [:]

    /// Last error from a refresh / send / read call, for inline display.
    @Published private(set) var lastError: String?

    // MARK: - Internals

    private var activeUserID: String
    private let backend: JourneyCommentBackend
    private var loadingThreadsJourneys: Set<String> = []
    private var loadingMessagesThreads: Set<String> = []
#if DEBUG
    private var debugSeededJourneys: Set<String> = []
#endif

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
        messageLoadPhaseByThread.removeAll()
        threadsLoadPhaseByJourney.removeAll()
        hasMoreOlderByThread.removeAll()
        loadingOlderByThread.removeAll()
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

    func messageLoadPhase(forThread threadKey: String) -> ThreadLoadPhase {
        messageLoadPhaseByThread[threadKey] ?? .idle
    }

    func hasMoreOlder(forThread threadKey: String) -> Bool {
        hasMoreOlderByThread[threadKey] ?? false
    }

    func isLoadingOlder(forThread threadKey: String) -> Bool {
        loadingOlderByThread[threadKey] ?? false
    }

    func threadsLoadPhase(forJourney journeyID: String) -> ThreadLoadPhase {
        threadsLoadPhaseByJourney[journeyID] ?? .idle
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
#if DEBUG
        if debugSeededJourneys.contains(journeyID) { return }
#endif
        guard !loadingThreadsJourneys.contains(journeyID) else { return }
        loadingThreadsJourneys.insert(journeyID)
        defer { loadingThreadsJourneys.remove(journeyID) }
        if (threadsByJourney[journeyID] ?? []).isEmpty {
            threadsLoadPhaseByJourney[journeyID] = .loading
        }
        do {
            let threads = try await backend.fetchThreads(
                journeyID: journeyID,
                viewerID: activeUserID,
                token: token
            )
            threadsByJourney[journeyID] = threads
            let count = threads.reduce(0) { $0 + $1.unreadCount }
            updateUnread(forJourney: journeyID, to: count)
            threadsLoadPhaseByJourney[journeyID] = .loaded
            lastError = nil
        } catch {
            if (threadsByJourney[journeyID] ?? []).isEmpty {
                threadsLoadPhaseByJourney[journeyID] = .failed
            }
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
#if DEBUG
        if debugSeededJourneys.contains(journeyID) { return }
#endif
        let threadKey = JourneyCommentThreadKey.make(
            journeyID: journeyID,
            userA: activeUserID,
            userB: otherUserID
        )
        guard !loadingMessagesThreads.contains(threadKey) else { return }
        loadingMessagesThreads.insert(threadKey)
        defer { loadingMessagesThreads.remove(threadKey) }
        // Phase tracking only applies to the initial page (before == nil);
        // pagination keeps the list visible and shouldn't toggle the phase.
        if before == nil {
            messageLoadPhaseByThread[threadKey] = .loading
        }
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
                // Full refresh of the most-recent page. Preserve any optimistic
                // messages still in flight / failed so a concurrent reload (the
                // sheet refreshes on every appear) can't drop a pending bubble.
                let pending = (messagesByThread[threadKey] ?? []).filter { $0.sendState != .sent }
                if pending.isEmpty {
                    messagesByThread[threadKey] = page
                } else {
                    let pageIDs = Set(page.map(\.id))
                    var merged = page
                    merged.append(contentsOf: pending.filter { !pageIDs.contains($0.id) })
                    merged.sort { $0.createdAt < $1.createdAt }
                    messagesByThread[threadKey] = merged
                }
            } else {
                let existing = messagesByThread[threadKey] ?? []
                // Page returns older messages; merge by id keeping ascending order.
                var merged = page
                let pageIDs = Set(page.map(\.id))
                merged.append(contentsOf: existing.filter { !pageIDs.contains($0.id) })
                merged.sort { $0.createdAt < $1.createdAt }
                messagesByThread[threadKey] = merged
            }
            // A full page back means there may be still-older messages to page to.
            hasMoreOlderByThread[threadKey] = page.count >= limit
            if before == nil {
                messageLoadPhaseByThread[threadKey] = .loaded
            }
            lastError = nil
        } catch {
            if before == nil {
                messageLoadPhaseByThread[threadKey] = .failed
            }
            lastError = error.localizedDescription
        }
    }

    /// Pages one batch of older messages into a thread, using the oldest
    /// confirmed message's timestamp as the cursor. No-op when there's nothing
    /// older or a fetch is already running. Drives the "load earlier" UI.
    func loadOlderMessages(journeyID: String, otherUserID: String, token: String?, limit: Int = 30) async {
        let threadKey = JourneyCommentThreadKey.make(
            journeyID: journeyID,
            userA: activeUserID,
            userB: otherUserID
        )
        guard hasMoreOlderByThread[threadKey] == true else { return }
        guard !loadingMessagesThreads.contains(threadKey) else { return }
        // Cursor off the oldest *confirmed* message; optimistic pending bubbles
        // carry a "now" timestamp and would otherwise skip the whole history.
        guard let oldest = (messagesByThread[threadKey] ?? [])
            .filter({ $0.sendState == .sent })
            .map(\.createdAt)
            .min() else { return }
        loadingOlderByThread[threadKey] = true
        defer { loadingOlderByThread[threadKey] = false }
        await loadMessages(
            journeyID: journeyID,
            otherUserID: otherUserID,
            token: token,
            before: oldest,
            limit: limit
        )
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
        let threadKey = JourneyCommentThreadKey.make(
            journeyID: journeyID,
            userA: activeUserID,
            userB: recipientID
        )
        // Optimistic insert: the bubble appears immediately in a `.sending`
        // state, before the network round-trip. On success it's reconciled with
        // the server comment; on failure it flips to `.failed` with a retry.
        let optimistic = JourneyComment(
            id: draftID,
            journeyID: journeyID,
            ownerID: ownerID,
            senderID: activeUserID,
            recipientID: recipientID,
            threadKey: threadKey,
            content: clipped,
            createdAt: Date(),
            readAt: nil,
            deletedAt: nil,
            sendState: .sending,
            clientDraftID: draftID
        )
        upsertMessage(optimistic, inThread: threadKey)
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
            reconcileSent(draftID: draftID, inThread: threadKey, with: comment)
            lastError = nil
            return comment
        } catch {
            markOptimisticFailed(draftID: draftID, inThread: threadKey)
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Re-sends a previously-failed optimistic message. Removes the failed
    /// bubble and runs a fresh optimistic send so it re-appears in `.sending`.
    func retrySend(_ failed: JourneyComment, token: String?) async {
        guard failed.sendState == .failed else { return }
        removeMessage(id: failed.id, inThread: failed.threadKey)
        _ = try? await send(
            journeyID: failed.journeyID,
            ownerID: failed.ownerID,
            recipientID: failed.recipientID,
            content: failed.content,
            token: token
        )
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
    /// Dev-only: injects fake thread(s) + mixed-direction messages directly
    /// into local state so the comment UI can be exercised without a second
    /// account or backend round-trips. `activeUserID` is treated as the
    /// owner side. Once a journey is seeded, this store skips backend reads
    /// for that journey so the fake data survives sheet reopens.
    func debugSeedFakeThreads(journeyID: String, friends: [(id: String, name: String)]) {
        guard !friends.isEmpty else { return }
        let ownerID = activeUserID

        // Per-friend conversation templates so each block looks distinct.
        // `fromFriend == true` means the friend sent it; `unread` only
        // applies to friend-sent messages.
        struct Line { let fromFriend: Bool; let content: String; let unread: Bool }
        let templates: [[Line]] = [
            [
                Line(fromFriend: true,  content: "在哪拍的?",          unread: false),
                Line(fromFriend: false, content: "外滩 18 号外面那条小路", unread: false),
                Line(fromFriend: true,  content: "哦哦看到了,周末一起去!", unread: true),
                Line(fromFriend: false, content: "好啊 顺便吃顿饭",      unread: false),
            ],
            [
                Line(fromFriend: true,  content: "这条路线可以发我吗?",   unread: false),
                Line(fromFriend: false, content: "刚刚分享了 看一下",     unread: false),
                Line(fromFriend: true,  content: "收到 谢谢!",          unread: true),
            ],
            [
                Line(fromFriend: true,  content: "天气真好",            unread: false),
                Line(fromFriend: false, content: "对啊 适合走路",        unread: false),
                Line(fromFriend: true,  content: "下次约我",            unread: false),
                Line(fromFriend: false, content: "没问题",              unread: false),
                Line(fromFriend: true,  content: "下周?",               unread: true),
            ],
        ]

        var threads: [JourneyCommentThread] = []
        var totalUnread = 0
        let baseTime = Date().addingTimeInterval(-1800)

        for (index, friend) in friends.enumerated() {
            let template = templates[index % templates.count]
            let threadKey = JourneyCommentThreadKey.make(
                journeyID: journeyID, userA: ownerID, userB: friend.id
            )
            let threadBase = baseTime.addingTimeInterval(Double(index) * 120)
            var msgs: [JourneyComment] = []
            var threadUnread = 0
            for (i, line) in template.enumerated() {
                let sender = line.fromFriend ? friend.id : ownerID
                let recipient = line.fromFriend ? ownerID : friend.id
                // Outgoing (owner→friend): pretend the friend has read it.
                // Incoming (friend→owner): readAt nil iff `unread`.
                let readAt: Date? = line.fromFriend ? (line.unread ? nil : Date()) : Date()
                msgs.append(JourneyComment(
                    id: UUID().uuidString,
                    journeyID: journeyID,
                    ownerID: ownerID,
                    senderID: sender,
                    recipientID: recipient,
                    threadKey: threadKey,
                    content: line.content,
                    createdAt: threadBase.addingTimeInterval(Double(i) * 30),
                    readAt: readAt,
                    deletedAt: nil
                ))
                if line.fromFriend && line.unread { threadUnread += 1 }
            }
            messagesByThread[threadKey] = msgs
            threads.append(JourneyCommentThread(
                threadKey: threadKey,
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: friend.id,
                otherDisplayName: friend.name,
                otherAvatarURL: nil,
                lastMessage: msgs.last,
                unreadCount: threadUnread
            ))
            totalUnread += threadUnread
        }

        threadsByJourney[journeyID] = threads
        updateUnread(forJourney: journeyID, to: totalUnread)
        debugSeededJourneys.insert(journeyID)
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

    /// Inserts or replaces a message by id, keeping the list ascending by time.
    private func upsertMessage(_ msg: JourneyComment, inThread threadKey: String) {
        var msgs = messagesByThread[threadKey] ?? []
        if let idx = msgs.firstIndex(where: { $0.id == msg.id }) {
            msgs[idx] = msg
        } else {
            msgs.append(msg)
        }
        msgs.sort { $0.createdAt < $1.createdAt }
        messagesByThread[threadKey] = msgs
        // The new message's thread may not be in threadsByJourney yet (e.g.
        // owner replies before threads list has been refreshed). The thread
        // summary list refreshes on next loadThreads call; UI typically doesn't
        // need the summary updated synchronously.
    }

    /// Swaps a confirmed server comment in for its optimistic placeholder.
    private func reconcileSent(draftID: String, inThread threadKey: String, with comment: JourneyComment) {
        var msgs = messagesByThread[threadKey] ?? []
        // A concurrent reload may already have merged the server comment in;
        // drop that duplicate before swapping the placeholder.
        msgs.removeAll { $0.id == comment.id && ($0.clientDraftID ?? $0.id) != draftID }
        var confirmed = comment
        confirmed.sendState = .sent
        confirmed.clientDraftID = nil
        if let idx = msgs.firstIndex(where: { ($0.clientDraftID ?? $0.id) == draftID }) {
            msgs[idx] = confirmed
        } else if !msgs.contains(where: { $0.id == confirmed.id }) {
            msgs.append(confirmed)
        }
        msgs.sort { $0.createdAt < $1.createdAt }
        messagesByThread[threadKey] = msgs
    }

    private func markOptimisticFailed(draftID: String, inThread threadKey: String) {
        guard var msgs = messagesByThread[threadKey] else { return }
        guard let idx = msgs.firstIndex(where: { ($0.clientDraftID ?? $0.id) == draftID }) else { return }
        msgs[idx].sendState = .failed
        messagesByThread[threadKey] = msgs
    }

    private func removeMessage(id: String, inThread threadKey: String) {
        guard var msgs = messagesByThread[threadKey] else { return }
        msgs.removeAll { $0.id == id }
        messagesByThread[threadKey] = msgs
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

/// Initial-load lifecycle for a thread list or message list. `.idle` means no
/// load has been attempted yet; treat it like `.loading` in the UI so the first
/// frame doesn't flash an empty state before the fetch starts.
enum ThreadLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum JourneyCommentStoreError: LocalizedError {
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .emptyContent: return "Comment is empty"
        }
    }
}
