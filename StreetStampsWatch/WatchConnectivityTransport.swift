import Foundation
import WatchConnectivity

final class WatchConnectivityTransport: NSObject {
    static let shared = WatchConnectivityTransport()

    private struct PersistedEnvelope: Codable {
        var id: String
        var payload: Data
        var eventRaw: String?
        var createdAt: Date
    }

    private enum Const {
        static let transferIDKey = "streetstamps.watch.transfer_id"
        static let queueFilename = "watch_journey_outbox_v1.json"
        static let avatarLoadoutPayloadKey = "streetstamps.watch.avatar_loadout.v1"
        static let avatarRequestKey = "streetstamps.watch.avatar_request.v1"
        static let maxOutboxItems = 1200
        static let maxOutboxBytes = 6 * 1024 * 1024
        static let maxProgressAgeSeconds: TimeInterval = 48 * 3600
        static let maxTransfersPerFlush = 60
    }

    private let stateQueue = DispatchQueue(label: "streetstamps.watch.transport.state")
    private var outbox: [PersistedEnvelope] = []
    private var inFlightIDs: Set<String> = []
    private var didRequestAvatarAfterActivation = false

    private override init() {
        super.init()
        loadOutboxFromDisk()
        activateSession()
    }

    func send(_ envelope: WatchJourneyEnvelope) {
        guard let userInfo = envelope.asUserInfo(),
              let payload = userInfo[WatchJourneyEnvelope.payloadKey] as? Data
        else { return }

        let item = PersistedEnvelope(
            id: envelope.eventID,
            payload: payload,
            eventRaw: envelope.event.rawValue,
            createdAt: Date()
        )

        stateQueue.sync {
            if !outbox.contains(where: { $0.id == item.id }) {
                outbox.append(item)
                pruneOutboxLocked(now: Date())
                saveOutboxToDiskLocked()
            }
        }

        flushPendingIfNeeded(session: WCSession.default)
    }

    func requestAvatarSyncIfPossible() {
        requestAvatarSync(session: WCSession.default, force: true)
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        session.activate()
    }

    private func flushPendingIfNeeded(session: WCSession) {
        guard session.activationState == .activated else { return }

        let toSend: [PersistedEnvelope] = stateQueue.sync {
            let candidates = outbox
                .filter { !inFlightIDs.contains($0.id) }
                .prefix(Const.maxTransfersPerFlush)
            for item in candidates {
                inFlightIDs.insert(item.id)
            }
            return Array(candidates)
        }

        guard !toSend.isEmpty else { return }

        for item in toSend {
            var userInfo: [String: Any] = [
                WatchJourneyEnvelope.payloadKey: item.payload,
                Const.transferIDKey: item.id
            ]

            if session.isReachable {
                session.sendMessage(userInfo, replyHandler: nil) { [weak self] _ in
                    self?.markAsNotInFlight(item.id)
                }
            }

            _ = session.transferUserInfo(userInfo)
            userInfo.removeAll(keepingCapacity: false)
        }
    }

    private func markAsDelivered(_ id: String) {
        stateQueue.sync {
            inFlightIDs.remove(id)
            outbox.removeAll(where: { $0.id == id })
            saveOutboxToDiskLocked()
        }
    }

    private func markAsNotInFlight(_ id: String) {
        _ = stateQueue.sync {
            inFlightIDs.remove(id)
        }
    }

    private func markTransferFailed(_ id: String) {
        _ = stateQueue.sync {
            inFlightIDs.remove(id)
        }
    }

    private func outboxURL() -> URL? {
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return root.appendingPathComponent(Const.queueFilename)
        } catch {
            return nil
        }
    }

    private func loadOutboxFromDisk() {
        guard let url = outboxURL(),
              let data = try? Data(contentsOf: url)
        else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let saved = try? decoder.decode([PersistedEnvelope].self, from: data) {
            stateQueue.sync {
                outbox = saved
                pruneOutboxLocked(now: Date())
                inFlightIDs.removeAll(keepingCapacity: false)
                saveOutboxToDiskLocked()
            }
        }
    }

    private func pruneOutboxLocked(now: Date) {
        outbox.removeAll {
            now.timeIntervalSince($0.createdAt) > Const.maxProgressAgeSeconds && isDroppableProgress($0)
        }

        while outbox.count > Const.maxOutboxItems {
            guard removeOldestDroppableProgressLocked() else { break }
        }

        while outboxTotalBytesLocked() > Const.maxOutboxBytes {
            guard removeOldestDroppableProgressLocked() else { break }
        }
    }

    private func outboxTotalBytesLocked() -> Int {
        outbox.reduce(0) { $0 + $1.payload.count }
    }

    private func removeOldestDroppableProgressLocked() -> Bool {
        guard let index = outbox.firstIndex(where: { isDroppableProgress($0) }) else { return false }
        let removed = outbox.remove(at: index)
        inFlightIDs.remove(removed.id)
        return true
    }

    private func isDroppableProgress(_ item: PersistedEnvelope) -> Bool {
        if let eventRaw = item.eventRaw {
            return eventRaw == WatchJourneyEvent.progress.rawValue
        }
        guard let envelope = try? Self.payloadDecoder.decode(WatchJourneyEnvelope.self, from: item.payload) else {
            return false
        }
        return envelope.event == .progress
    }

    private static let payloadDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func saveOutboxToDiskLocked() {
        guard let url = outboxURL() else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(outbox) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func requestAvatarSync(session: WCSession, force: Bool = false) {
        guard session.activationState == .activated else { return }
        guard session.isReachable else { return }
        if didRequestAvatarAfterActivation && !force { return }

        let message: [String: Any] = [Const.avatarRequestKey: true]
        session.sendMessage(message) { [weak self] reply in
            self?.handleApplicationContext(reply)
        } errorHandler: { _ in
            // If counterpart is temporarily unreachable, we'll retry on next reachability change.
        }

        didRequestAvatarAfterActivation = true
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        _ = activationState
        _ = error
        didRequestAvatarAfterActivation = false
        handleApplicationContext(session.receivedApplicationContext)
        flushPendingIfNeeded(session: session)
        requestAvatarSync(session: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        flushPendingIfNeeded(session: session)
        requestAvatarSync(session: session)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        _ = session
        handleApplicationContext(applicationContext)
    }

    func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        _ = session
        guard let id = userInfoTransfer.userInfo[Const.transferIDKey] as? String,
              !id.isEmpty
        else { return }

        if error == nil {
            markAsDelivered(id)
        } else {
            markTransferFailed(id)
        }

        flushPendingIfNeeded(session: WCSession.default)
    }

    private func handleApplicationContext(_ context: [String: Any]) {
        guard let data = context[Const.avatarLoadoutPayloadKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchAvatarLoadout.self, from: data)
        else { return }

        DispatchQueue.main.async {
            WatchAvatarLoadoutStore.save(decoded)
        }
    }
}
