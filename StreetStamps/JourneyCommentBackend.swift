import Foundation

/// Abstraction over the journey-comment backend. Step 1 ships a mock impl so
/// the iOS UI can be developed and reviewed without the backend in place.
/// Step 4 swaps in a `RESTJourneyCommentBackend` that hits the real endpoints
/// — the protocol shape is intentionally close to those endpoints so the swap
/// is mechanical.
protocol JourneyCommentBackend: Sendable {
    /// Per-journey unread count for the viewer. Called once at startup.
    func fetchUnreadSummary(viewerID: String, token: String?) async throws -> [String: Int]

    /// Threads on `journeyID` that involve `viewerID` (either side).
    /// - For the owner: returns one thread per friend who has posted.
    /// - For a viewer (friend): returns at most one thread (viewer ↔ owner).
    func fetchThreads(journeyID: String, viewerID: String, token: String?) async throws -> [JourneyCommentThread]

    /// Messages within a single thread, ordered ascending by `createdAt`.
    /// `before` paginates older messages; nil returns the most recent page.
    func fetchMessages(
        journeyID: String,
        otherUserID: String,
        viewerID: String,
        before: Date?,
        limit: Int,
        token: String?
    ) async throws -> [JourneyComment]

    func send(
        journeyID: String,
        ownerID: String,
        recipientID: String,
        senderID: String,
        content: String,
        clientDraftID: String,
        token: String?
    ) async throws -> JourneyComment

    func markRead(
        journeyID: String,
        otherUserID: String,
        viewerID: String,
        token: String?
    ) async throws

    func deleteComment(id: String, viewerID: String, token: String?) async throws
}

/// Real REST implementation. The token-authenticated backend identifies the
/// viewer server-side, so `viewerID` is unused here.
actor RESTJourneyCommentBackend: JourneyCommentBackend {
    static let shared = RESTJourneyCommentBackend()

    private init() {}

    func fetchUnreadSummary(viewerID: String, token: String?) async throws -> [String: Int] {
        guard let token, !token.isEmpty else { return [:] }
        let response = try await BackendAPIClient.shared.fetchJourneyCommentUnreadSummary(token: token)
        return response.summary
    }

    func fetchThreads(journeyID: String, viewerID: String, token: String?) async throws -> [JourneyCommentThread] {
        guard let token, !token.isEmpty else { return [] }
        let response = try await BackendAPIClient.shared.fetchJourneyCommentThreads(
            token: token,
            journeyID: journeyID
        )
        return response.threads.map { dto in
            JourneyCommentThread(
                threadKey: dto.threadKey,
                journeyID: dto.journeyID,
                ownerID: dto.ownerID,
                otherUserID: dto.otherUserID,
                otherDisplayName: nil,
                otherAvatarURL: nil,
                lastMessage: dto.lastMessage,
                unreadCount: dto.unreadCount
            )
        }
    }

    func fetchMessages(
        journeyID: String,
        otherUserID: String,
        viewerID: String,
        before: Date?,
        limit: Int,
        token: String?
    ) async throws -> [JourneyComment] {
        guard let token, !token.isEmpty else { return [] }
        let response = try await BackendAPIClient.shared.fetchJourneyCommentMessages(
            token: token,
            journeyID: journeyID,
            otherUserID: otherUserID,
            before: before,
            limit: limit
        )
        return response.messages
    }

    func send(
        journeyID: String,
        ownerID: String,
        recipientID: String,
        senderID: String,
        content: String,
        clientDraftID: String,
        token: String?
    ) async throws -> JourneyComment {
        guard let token, !token.isEmpty else {
            throw BackendAPIError.server("missing access token")
        }
        let response = try await BackendAPIClient.shared.sendJourneyComment(
            token: token,
            journeyID: journeyID,
            body: BackendSendJourneyCommentRequest(
                ownerID: ownerID,
                recipientID: recipientID,
                content: content,
                clientDraftID: clientDraftID
            )
        )
        return response.comment
    }

    func markRead(
        journeyID: String,
        otherUserID: String,
        viewerID: String,
        token: String?
    ) async throws {
        guard let token, !token.isEmpty else { return }
        try await BackendAPIClient.shared.markJourneyCommentThreadRead(
            token: token,
            journeyID: journeyID,
            otherUserID: otherUserID
        )
    }

    func deleteComment(id: String, viewerID: String, token: String?) async throws {
        guard let token, !token.isEmpty else { return }
        try await BackendAPIClient.shared.deleteJourneyComment(token: token, id: id)
    }
}

/// In-memory mock backend for development. Persists state for the lifetime of
/// the process only; restarting the simulator resets everything.
actor MockJourneyCommentBackend: JourneyCommentBackend {
    static let shared = MockJourneyCommentBackend()

    private var comments: [JourneyComment] = []
    private var friendNames: [String: String] = [:]
    private let simulatedLatencyMs: UInt64 = 80

    private init() {}

    // MARK: - Dev helpers

    /// Seed a few sample threads on a given journey so UI work has something
    /// to render. Idempotent on (journeyID, ownerID).
    func seedSampleData(journeyID: String, ownerID: String, friends: [(id: String, name: String)]) {
        guard !comments.contains(where: { $0.journeyID == journeyID && $0.ownerID == ownerID }) else { return }
        for (idx, friend) in friends.enumerated() {
            friendNames[friend.id] = friend.name
            let threadKey = JourneyCommentThreadKey.make(journeyID: journeyID, userA: ownerID, userB: friend.id)
            let baseTime = Date().addingTimeInterval(-Double(idx) * 3600 - 600)
            // First message: friend → owner
            comments.append(JourneyComment(
                id: UUID().uuidString,
                journeyID: journeyID,
                ownerID: ownerID,
                senderID: friend.id,
                recipientID: ownerID,
                threadKey: threadKey,
                content: idx == 0 ? "在哪拍的？" : (idx == 1 ? "好看！" : "你看"),
                createdAt: baseTime,
                readAt: nil,
                deletedAt: nil
            ))
            // For the first friend, add an owner reply + a follow-up so the
            // UI has a mixed-direction thread to render.
            if idx == 0 {
                comments.append(JourneyComment(
                    id: UUID().uuidString,
                    journeyID: journeyID,
                    ownerID: ownerID,
                    senderID: ownerID,
                    recipientID: friend.id,
                    threadKey: threadKey,
                    content: "外滩 18 号外",
                    createdAt: baseTime.addingTimeInterval(120),
                    readAt: Date(),
                    deletedAt: nil
                ))
                comments.append(JourneyComment(
                    id: UUID().uuidString,
                    journeyID: journeyID,
                    ownerID: ownerID,
                    senderID: friend.id,
                    recipientID: ownerID,
                    threadKey: threadKey,
                    content: "哦哦看到了",
                    createdAt: baseTime.addingTimeInterval(300),
                    readAt: nil,
                    deletedAt: nil
                ))
            }
        }
    }

    func reset() {
        comments.removeAll()
        friendNames.removeAll()
    }

    // MARK: - Protocol

    func fetchUnreadSummary(viewerID: String, token: String?) async throws -> [String: Int] {
        try await simulateLatency()
        var result: [String: Int] = [:]
        for c in comments where c.recipientID == viewerID && c.readAt == nil && c.deletedAt == nil {
            result[c.journeyID, default: 0] += 1
        }
        return result
    }

    func fetchThreads(journeyID: String, viewerID: String, token: String?) async throws -> [JourneyCommentThread] {
        try await simulateLatency()
        let journeyComments = comments.filter { $0.journeyID == journeyID && $0.deletedAt == nil }
        // Group by threadKey.
        var grouped: [String: [JourneyComment]] = [:]
        for c in journeyComments where c.senderID == viewerID || c.recipientID == viewerID {
            grouped[c.threadKey, default: []].append(c)
        }
        let threads: [JourneyCommentThread] = grouped.compactMap { (threadKey, msgs) in
            let sorted = msgs.sorted { $0.createdAt < $1.createdAt }
            guard let last = sorted.last else { return nil }
            let ownerID = last.ownerID
            let otherID = (sorted.first?.senderID == viewerID)
                ? sorted.first!.recipientID
                : sorted.first!.senderID
            let unread = sorted.filter { $0.recipientID == viewerID && $0.readAt == nil }.count
            return JourneyCommentThread(
                threadKey: threadKey,
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: otherID,
                otherDisplayName: friendNames[otherID],
                otherAvatarURL: nil,
                lastMessage: last,
                unreadCount: unread
            )
        }
        // Unread first, then most-recent first.
        return threads.sorted { lhs, rhs in
            if (lhs.unreadCount > 0) != (rhs.unreadCount > 0) {
                return lhs.unreadCount > 0
            }
            return (lhs.lastMessage?.createdAt ?? .distantPast) > (rhs.lastMessage?.createdAt ?? .distantPast)
        }
    }

    func fetchMessages(
        journeyID: String,
        otherUserID: String,
        viewerID: String,
        before: Date?,
        limit: Int,
        token: String?
    ) async throws -> [JourneyComment] {
        try await simulateLatency()
        let threadKey = JourneyCommentThreadKey.make(journeyID: journeyID, userA: viewerID, userB: otherUserID)
        var filtered = comments.filter { $0.threadKey == threadKey && $0.deletedAt == nil }
        if let before {
            filtered = filtered.filter { $0.createdAt < before }
        }
        filtered.sort { $0.createdAt < $1.createdAt }
        // Take the last `limit` items so the returned slice is the most recent
        // page when `before` is nil, or the page immediately older otherwise.
        if filtered.count > limit {
            filtered = Array(filtered.suffix(limit))
        }
        return filtered
    }

    func send(
        journeyID: String,
        ownerID: String,
        recipientID: String,
        senderID: String,
        content: String,
        clientDraftID: String,
        token: String?
    ) async throws -> JourneyComment {
        try await simulateLatency()
        if let existing = comments.first(where: { $0.id == clientDraftID }) {
            return existing
        }
        let threadKey = JourneyCommentThreadKey.make(journeyID: journeyID, userA: senderID, userB: recipientID)
        let comment = JourneyComment(
            id: clientDraftID,
            journeyID: journeyID,
            ownerID: ownerID,
            senderID: senderID,
            recipientID: recipientID,
            threadKey: threadKey,
            content: content,
            createdAt: Date(),
            readAt: nil,
            deletedAt: nil
        )
        comments.append(comment)
        return comment
    }

    func markRead(journeyID: String, otherUserID: String, viewerID: String, token: String?) async throws {
        try await simulateLatency()
        let threadKey = JourneyCommentThreadKey.make(journeyID: journeyID, userA: viewerID, userB: otherUserID)
        let now = Date()
        for i in comments.indices where comments[i].threadKey == threadKey
            && comments[i].recipientID == viewerID
            && comments[i].readAt == nil {
            comments[i].readAt = now
        }
    }

    func deleteComment(id: String, viewerID: String, token: String?) async throws {
        try await simulateLatency()
        guard let idx = comments.firstIndex(where: { $0.id == id }) else { return }
        guard comments[idx].senderID == viewerID else { return }
        comments[idx].deletedAt = Date()
    }

    private func simulateLatency() async throws {
        try await Task.sleep(nanoseconds: simulatedLatencyMs * 1_000_000)
    }
}
