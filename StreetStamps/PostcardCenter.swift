import Foundation
import os

extension Notification.Name {
    static let postcardSentGoToInbox = Notification.Name("postcardSentGoToInbox")
}

enum PostcardSendErrorPresentation {
    static func message(for error: Error, localize: (String) -> String = L10n.t) -> String {
        guard let backendError = error as? BackendAPIError else {
            return localize("postcard_send_failed")
        }

        switch backendError.responseCode {
        case "city_friend_quota_exceeded":
            return localize("postcard_quota_friend_limit_reached")
        case "city_total_quota_exceeded":
            return localize("postcard_quota_city_limit_reached")
        default:
            return localize("postcard_send_failed")
        }
    }
}

@MainActor
final class PostcardCenter: ObservableObject {
    private struct SendTimingProbe {
        private let startedAt = ContinuousClock.now
        private let clock = ContinuousClock()
        var photoResolveDurationMs = 0
        var uploadDurationMs = 0
        var sendRequestDurationMs = 0

        func snapshot() -> PostcardDraft.SendDiagnostics {
            PostcardDraft.SendDiagnostics(
                photoResolveDurationMs: photoResolveDurationMs,
                uploadDurationMs: uploadDurationMs,
                sendRequestDurationMs: sendRequestDurationMs,
                totalDurationMs: Self.elapsedMilliseconds(since: startedAt, now: clock.now),
                completedAt: Date()
            )
        }

        static func elapsedMilliseconds(
            since start: ContinuousClock.Instant,
            now: ContinuousClock.Instant
        ) -> Int {
            let duration = start.duration(to: now)
            let millisecondsFromSeconds = duration.components.seconds * 1_000
            let millisecondsFromAttoseconds = duration.components.attoseconds / 1_000_000_000_000_000
            return max(1, Int(millisecondsFromSeconds + millisecondsFromAttoseconds))
        }
    }

    @Published private(set) var drafts: [PostcardDraft] = []
    @Published private(set) var sentItems: [BackendPostcardMessageDTO] = []
    @Published private(set) var receivedItems: [BackendPostcardMessageDTO] = []
    @Published private(set) var lastSyncError: String? = nil

    private let logger = Logger(subsystem: "StreetStamps", category: "PostcardSend")

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
            sendDiagnostics: nil,
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

    func retry(draftID: String, token: String?, allowedCityIDs: [String], cityJourneyCount: Int) async {
        await enqueueSend(
            draftID: draftID,
            token: token,
            allowedCityIDs: allowedCityIDs,
            cityJourneyCount: cityJourneyCount,
            increaseRetry: true
        )
    }

    func enqueueSend(draftID: String, token: String?, allowedCityIDs: [String], cityJourneyCount: Int) async {
        await enqueueSend(
            draftID: draftID,
            token: token,
            allowedCityIDs: allowedCityIDs,
            cityJourneyCount: cityJourneyCount,
            increaseRetry: false
        )
    }

    func enqueueSendInBackground(draftID: String, token: String?, allowedCityIDs: [String], cityJourneyCount: Int) {
        if let idx = drafts.firstIndex(where: { $0.draftID == draftID }) {
            var draft = drafts[idx]
            draft.status = .sending
            draft.lastError = nil
            draft.updatedAt = Date()
            drafts[idx] = draft
            persist()
        }
        Task { [weak self] in
            await self?.enqueueSend(
                draftID: draftID,
                token: token,
                allowedCityIDs: allowedCityIDs,
                cityJourneyCount: cityJourneyCount,
                increaseRetry: false
            )
        }
    }

    func refreshFromBackend(token: String?) async {
        guard let token, !token.isEmpty else { return }
        do {
            async let sentTask = BackendAPIClient.shared.fetchPostcards(token: token, box: "sent")
            async let receivedTask = BackendAPIClient.shared.fetchPostcards(token: token, box: "received")
            let (sent, received) = try await (sentTask, receivedTask)
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

    private func enqueueSend(
        draftID: String,
        token: String?,
        allowedCityIDs: [String],
        cityJourneyCount: Int,
        increaseRetry: Bool
    ) async {
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
            var timingProbe = SendTimingProbe()
            let photoResolveStartedAt = ContinuousClock.now
            let photoResolution = try await resolvePhotoURL(
                source: draft.photoLocalPath,
                token: token
            )
            timingProbe.photoResolveDurationMs = SendTimingProbe.elapsedMilliseconds(
                since: photoResolveStartedAt,
                now: ContinuousClock.now
            )
            timingProbe.uploadDurationMs = photoResolution.uploadDurationMs
            let payload = SendPostcardRequest(
                clientDraftID: draft.clientDraftID,
                toUserID: draft.toUserID,
                cityID: draft.cityID,
                cityJourneyCount: max(1, cityJourneyCount),
                cityName: draft.cityName,
                messageText: String(draft.message.prefix(80)),
                photoURL: photoResolution.url,
                allowedCityIDs: allowedCityIDs
            )
            let sendStartedAt = ContinuousClock.now
            let response = try await BackendAPIClient.shared.sendPostcard(token: token, req: payload)
            timingProbe.sendRequestDurationMs = SendTimingProbe.elapsedMilliseconds(
                since: sendStartedAt,
                now: ContinuousClock.now
            )
            let diagnostics = timingProbe.snapshot()

            guard let currentIndex = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
            var current = drafts[currentIndex]
            current.photoLocalPath = photoResolution.url
            current.status = .sent
            current.messageID = response.messageID
            current.sentAt = response.sentAt
            current.sendDiagnostics = diagnostics
            current.lastError = nil
            current.updatedAt = Date()
            drafts[currentIndex] = current
            persist()
            logSendDiagnostics(status: "sent", draftID: draftID, diagnostics: diagnostics)
            // Keep "send" completion snappy; refresh inbox in background.
            Task { [weak self] in
                await self?.refreshFromBackend(token: token)
            }
        } catch {
            guard let currentIndex = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
            var current = drafts[currentIndex]
            current.status = .failed
            current.lastError = PostcardSendErrorPresentation.message(for: error)
            if current.sendDiagnostics == nil {
                current.sendDiagnostics = SendTimingProbe().snapshot()
            }
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

    private func resolvePhotoURL(
        source: String,
        token: String
    ) async throws -> (url: String, uploadDurationMs: Int) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendAPIError.server("postcard image missing")
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return (trimmed, 0)
        }

        let fileURL = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BackendAPIError.server("postcard image not found")
        }

        let data = try await Self.readFileDataAsync(from: fileURL)
        let mime = mimeType(for: fileURL.pathExtension)
        let uploadStart = ContinuousClock.now
        let upload = try await BackendAPIClient.shared.uploadMedia(
            token: token,
            data: data,
            fileName: fileURL.lastPathComponent,
            mimeType: mime
        )
        return (
            upload.url,
            SendTimingProbe.elapsedMilliseconds(since: uploadStart, now: ContinuousClock.now)
        )
    }

    private func logSendDiagnostics(status: String, draftID: String, diagnostics: PostcardDraft.SendDiagnostics) {
        logger.log(
            "[PostcardTiming] status=\(status, privacy: .public) draftID=\(draftID, privacy: .public) prepare=\(diagnostics.photoResolveDurationMs)ms upload=\(diagnostics.uploadDurationMs)ms send=\(diagnostics.sendRequestDurationMs)ms total=\(diagnostics.totalDurationMs)ms"
        )
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
