import Foundation

@MainActor
final class PostcardCenter: ObservableObject {
    @Published private(set) var drafts: [PostcardDraft] = []
    @Published private(set) var sentItems: [BackendPostcardMessageDTO] = []
    @Published private(set) var receivedItems: [BackendPostcardMessageDTO] = []

    private var activeUserID: String

    init(userID: String) {
        self.activeUserID = userID
        self.drafts = PostcardDraftStore.load(userID: userID)
    }

    func switchUser(_ userID: String) {
        guard !userID.isEmpty, userID != activeUserID else { return }
        activeUserID = userID
        drafts = PostcardDraftStore.load(userID: userID)
        sentItems = []
        receivedItems = []
    }

    func createDraft(
        toUserID: String,
        cityID: String,
        cityName: String,
        photoLocalPath: String,
        message: String
    ) -> PostcardDraft {
        let now = Date()
        let id = UUID().uuidString
        let draft = PostcardDraft(
            draftID: id,
            clientDraftID: id,
            toUserID: toUserID,
            cityID: cityID,
            cityName: cityName,
            photoLocalPath: photoLocalPath,
            message: String(message.prefix(80)),
            status: .draft,
            retryCount: 0,
            lastError: nil,
            messageID: nil,
            sentAt: nil,
            createdAt: now,
            updatedAt: now
        )
        upsert(draft)
        return draft
    }

    func updateDraft(
        draftID: String,
        cityID: String,
        cityName: String,
        photoLocalPath: String,
        message: String
    ) {
        guard var draft = drafts.first(where: { $0.draftID == draftID }) else { return }
        guard draft.status == .draft || draft.status == .failed else { return }
        draft.cityID = cityID
        draft.cityName = cityName
        draft.photoLocalPath = photoLocalPath
        draft.message = String(message.prefix(80))
        draft.updatedAt = Date()
        upsert(draft)
    }

    func removeDraft(draftID: String) {
        drafts.removeAll { $0.draftID == draftID }
        persist()
    }

    func retry(draftID: String, token: String?, allowedCityIDs: [String]) async {
        await enqueueSend(draftID: draftID, token: token, allowedCityIDs: allowedCityIDs, increaseRetry: true)
    }

    func enqueueSend(draftID: String, token: String?, allowedCityIDs: [String]) async {
        await enqueueSend(draftID: draftID, token: token, allowedCityIDs: allowedCityIDs, increaseRetry: false)
    }

    func refreshFromBackend(token: String?) async {
        guard let token, !token.isEmpty else { return }
        do {
            let sent = try await BackendAPIClient.shared.fetchPostcards(token: token, box: "sent")
            let received = try await BackendAPIClient.shared.fetchPostcards(token: token, box: "received")
            sentItems = sent.items.sorted(by: { $0.sentAt > $1.sentAt })
            receivedItems = received.items.sorted(by: { $0.sentAt > $1.sentAt })
        } catch {
            // Keep local state stable; caller decides whether to surface error.
        }
    }

    private func enqueueSend(draftID: String, token: String?, allowedCityIDs: [String], increaseRetry: Bool) async {
        guard let idx = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
        guard let token, !token.isEmpty else {
            var draft = drafts[idx]
            draft.status = .failed
            draft.lastError = "请先登录"
            draft.updatedAt = Date()
            if increaseRetry { draft.retryCount += 1 }
            drafts[idx] = draft
            persist()
            return
        }

        var draft = drafts[idx]
        draft.status = .sending
        draft.lastError = nil
        draft.updatedAt = Date()
        if increaseRetry { draft.retryCount += 1 }
        drafts[idx] = draft
        persist()

        do {
            let payload = SendPostcardRequest(
                clientDraftID: draft.clientDraftID,
                toUserID: draft.toUserID,
                cityID: draft.cityID,
                cityName: draft.cityName,
                messageText: String(draft.message.prefix(80)),
                photoURL: draft.photoLocalPath,
                allowedCityIDs: allowedCityIDs
            )
            let response = try await BackendAPIClient.shared.sendPostcard(token: token, req: payload)

            guard let currentIndex = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
            var current = drafts[currentIndex]
            current.status = .sent
            current.messageID = response.messageID
            current.sentAt = response.sentAt
            current.lastError = nil
            current.updatedAt = Date()
            drafts[currentIndex] = current
            persist()
            await refreshFromBackend(token: token)
        } catch {
            guard let currentIndex = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
            var current = drafts[currentIndex]
            current.status = .failed
            current.lastError = error.localizedDescription
            current.updatedAt = Date()
            drafts[currentIndex] = current
            persist()
        }
    }

    private func upsert(_ draft: PostcardDraft) {
        if let idx = drafts.firstIndex(where: { $0.draftID == draft.draftID }) {
            drafts[idx] = draft
        } else {
            drafts.insert(draft, at: 0)
        }
        drafts.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        PostcardDraftStore.save(drafts, userID: activeUserID)
    }
}
