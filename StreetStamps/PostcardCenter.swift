import Foundation

extension Notification.Name {
    static let postcardSentGoToInbox = Notification.Name("postcardSentGoToInbox")
}

@MainActor
final class PostcardCenter: ObservableObject {
    @Published private(set) var drafts: [PostcardDraft] = []
    @Published private(set) var sentItems: [BackendPostcardMessageDTO] = []
    @Published private(set) var receivedItems: [BackendPostcardMessageDTO] = []
    @Published private(set) var lastSyncError: String? = nil

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
        lastSyncError = nil
    }

    func createDraft(
        toUserID: String,
        toDisplayName: String?,
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
            toDisplayName: toDisplayName,
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
            lastSyncError = nil
        } catch {
            if Self.isCancellationError(error) {
                return
            }
            // Keep local state stable but surface a concise sync error for UI diagnostics.
            let msg = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            lastSyncError = msg.isEmpty ? "明信片同步失败" : msg
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
            let remotePhotoURL = try await resolvePhotoURL(
                source: draft.photoLocalPath,
                token: token
            )
            let payload = SendPostcardRequest(
                clientDraftID: draft.clientDraftID,
                toUserID: draft.toUserID,
                cityID: draft.cityID,
                cityName: draft.cityName,
                messageText: String(draft.message.prefix(80)),
                photoURL: remotePhotoURL,
                allowedCityIDs: allowedCityIDs
            )
            let response = try await BackendAPIClient.shared.sendPostcard(token: token, req: payload)

            guard let currentIndex = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
            var current = drafts[currentIndex]
            current.photoLocalPath = remotePhotoURL
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

    private func resolvePhotoURL(source: String, token: String) async throws -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendAPIError.server("postcard image missing")
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }

        let fileURL = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BackendAPIError.server("postcard image not found")
        }

        let data = try await Self.readFileDataAsync(from: fileURL)
        let mime = mimeType(for: fileURL.pathExtension)
        let upload = try await BackendAPIClient.shared.uploadMedia(
            token: token,
            data: data,
            fileName: fileURL.lastPathComponent,
            mimeType: mime
        )
        return upload.url
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    private nonisolated static func readFileDataAsync(from url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
