import Foundation
import SwiftUI

enum JourneyPublishStatus: Equatable {
    case idle
    case sending(journeyID: String, title: String)
    case success(journeyID: String, title: String)
    case failed(journeyID: String, title: String, errorMessage: String)

    var journeyID: String? {
        switch self {
        case .idle: return nil
        case .sending(let id, _), .success(let id, _), .failed(let id, _, _): return id
        }
    }

    var isSending: Bool {
        if case .sending = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
final class JourneyPublishStore: ObservableObject {
    @Published private(set) var status: JourneyPublishStatus = .idle

    private var publishTask: Task<Void, Never>?
    private var publishStartedAt: Date?
    private var dismissTask: Task<Void, Never>?
    private var lastFailedJourney: JourneyRoute?
    private var lastFailedSessionStore: UserSessionStore?
    private var lastFailedCityCache: CityCache?
    private var lastFailedJourneyStore: JourneyStore?

    /// `isExplicitVisibilityChange` must be `true` when the user has explicitly changed
    /// visibility (including to `.private`). Pass `false` for implicit publishes like
    /// journey completion, where private journeys should not be synced to the backend.
    func publish(
        journey: JourneyRoute,
        sessionStore: UserSessionStore,
        cityCache: CityCache,
        journeyStore: JourneyStore,
        isExplicitVisibilityChange: Bool = false
    ) {
        let title = journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (journey.customTitle ?? journey.displayCityName)
            : journey.displayCityName

        guard journey.visibility == .public || journey.visibility == .friendsOnly || isExplicitVisibilityChange else { return }
        guard BackendConfig.isEnabled,
              sessionStore.currentAccessToken?.isEmpty == false else { return }

        // Auto-complete ongoing journeys before publishing.
        // Priority: last memory time → last file persist time → now.
        var journey = journey
        if journey.endTime == nil {
            let fallbackEnd = journey.memories.map(\.timestamp).max()
                ?? journeyStore.lastPersistedAt(journeyID: journey.id)
                ?? Date()
            journey.endTime = fallbackEnd
            journeyStore.applyBulkCompletedUpdates([journey])
        }

        publishTask?.cancel()
        publishTask = nil
        dismissTask?.cancel()
        status = .sending(journeyID: journey.id, title: title)
        publishStartedAt = Date()
        lastFailedJourney = journey
        lastFailedSessionStore = sessionStore
        lastFailedCityCache = cityCache
        lastFailedJourneyStore = journeyStore

        let journeyID = journey.id
        publishTask = Task {
            do {
                let urlCache = try await JourneyCloudMigrationService.syncJourneyVisibilityChange(
                    journey: journey,
                    sessionStore: sessionStore,
                    cityCache: cityCache,
                    urlCacheObserver: { [weak journeyStore] jid, cache in
                        // Apply URL cache as soon as photos are uploaded, before the
                        // migration payload is sent. If migrateJourneys times out, the
                        // next retry will see populated remoteImageURLs and skip re-uploads.
                        guard let journeyStore else { return }
                        Task { @MainActor [journeyStore] in
                            JourneyPublishStore.applyRemoteURLCache(
                                cache, journeyID: jid, journeyStore: journeyStore
                            )
                        }
                    }
                )
                // Also apply on success (idempotent — ensures any racing update is complete).
                if let cache = urlCache[journeyID] {
                    Self.applyRemoteURLCache(cache, journeyID: journeyID, journeyStore: journeyStore)
                }
                // Stamp sharedAt on first successful publish (visibility was friendsOnly/public).
                if journey.visibility == .public || journey.visibility == .friendsOnly {
                    Self.applySharedAtIfNeeded(journeyID: journeyID, journeyStore: journeyStore)
                }
                status = .success(journeyID: journeyID, title: title)
                lastFailedJourney = nil
                scheduleDismiss()
            } catch {
                let message = LocalizedErrorHelper.message(for: error)
                status = .failed(
                    journeyID: journeyID,
                    title: title,
                    errorMessage: message
                )
                lastFailedJourney = journey
            }
        }
    }

    /// Restores a .failed banner state for a journey whose local visibility was
    /// set to friends-only/public but whose backend publish never confirmed
    /// (sharedAt == nil). No network work is started — the user decides whether
    /// to Retry or Save Private via the banner buttons. Intended for app
    /// kill/relaunch recovery where the in-memory publish state was lost.
    func restoreUnconfirmedPublish(
        journey: JourneyRoute,
        sessionStore: UserSessionStore,
        cityCache: CityCache,
        journeyStore: JourneyStore
    ) {
        guard case .idle = status else { return }
        let title = journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (journey.customTitle ?? journey.displayCityName)
            : journey.displayCityName
        lastFailedJourney = journey
        lastFailedSessionStore = sessionStore
        lastFailedCityCache = cityCache
        lastFailedJourneyStore = journeyStore
        status = .failed(journeyID: journey.id, title: title, errorMessage: "")
    }

    /// Call when the app returns to foreground. If publishing has been stuck for over
    /// 60 seconds (e.g. app was suspended mid-upload and background session failed),
    /// cancels and retries automatically.
    func handleSceneActivation() {
        guard status.isSending,
              let startedAt = publishStartedAt,
              Date().timeIntervalSince(startedAt) > 60 else { return }
        publishTask?.cancel()
        publishTask = nil
        retry()
    }

    func retry() {
        guard let failed = lastFailedJourney,
              let sessionStore = lastFailedSessionStore,
              let cityCache = lastFailedCityCache,
              let journeyStore = lastFailedJourneyStore else { return }
        // Use the latest version from store instead of the stale snapshot.
        let journey = journeyStore.journeys.first(where: { $0.id == failed.id }) ?? failed
        // Treat all retries as explicit visibility changes (the original was user-initiated).
        publish(
            journey: journey,
            sessionStore: sessionStore,
            cityCache: cityCache,
            journeyStore: journeyStore,
            isExplicitVisibilityChange: true
        )
    }

    func fallbackToPrivate() {
        guard let journey = lastFailedJourney,
              let journeyStore = lastFailedJourneyStore else {
            dismiss()
            return
        }

        var updated = journey
        updated.visibility = .private
        journeyStore.applyBulkCompletedUpdates([updated])

        lastFailedJourney = nil
        lastFailedSessionStore = nil
        lastFailedCityCache = nil
        lastFailedJourneyStore = nil
        dismiss()
    }

    func dismiss() {
        publishTask?.cancel()
        publishTask = nil
        publishStartedAt = nil
        dismissTask?.cancel()
        status = .idle
        lastFailedJourney = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            status = .idle
        }
    }

    private static func applySharedAtIfNeeded(journeyID: String, journeyStore: JourneyStore) {
        guard let idx = journeyStore.journeys.firstIndex(where: { $0.id == journeyID }),
              journeyStore.journeys[idx].sharedAt == nil else { return }
        var j = journeyStore.journeys[idx]
        j.sharedAt = Date()
        journeyStore.applyBulkCompletedUpdates([j])
    }

    private static func applyRemoteURLCache(
        _ cache: JourneyCloudMigrationService.JourneyRemoteURLCache,
        journeyID: String,
        journeyStore: JourneyStore
    ) {
        guard let idx = journeyStore.journeys.firstIndex(where: { $0.id == journeyID }) else { return }
        var j = journeyStore.journeys[idx]
        var changed = false
        for memIdx in j.memories.indices {
            if let urls = cache.memoryURLs[j.memories[memIdx].id], urls != j.memories[memIdx].remoteImageURLs {
                j.memories[memIdx].remoteImageURLs = urls
                changed = true
            }
        }
        if cache.overallImageURLs != j.overallMemoryRemoteImageURLs {
            j.overallMemoryRemoteImageURLs = cache.overallImageURLs
            changed = true
        }
        if changed {
            journeyStore.applyBulkCompletedUpdates([j])
        }
    }
}
