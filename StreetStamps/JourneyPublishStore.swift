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

        dismissTask?.cancel()
        status = .sending(journeyID: journey.id, title: title)
        lastFailedJourney = journey
        lastFailedSessionStore = sessionStore
        lastFailedCityCache = cityCache
        lastFailedJourneyStore = journeyStore

        Task {
            do {
                let urlCache = try await JourneyCloudMigrationService.syncJourneyVisibilityChange(
                    journey: journey,
                    sessionStore: sessionStore,
                    cityCache: cityCache
                )
                // Cache remote URLs locally so future republish can skip missing local files.
                if let cache = urlCache[journey.id] {
                    Self.applyRemoteURLCache(cache, journeyID: journey.id, journeyStore: journeyStore)
                }
                // Stamp sharedAt on first successful publish (visibility was friendsOnly/public).
                if journey.visibility == .public || journey.visibility == .friendsOnly {
                    Self.applySharedAtIfNeeded(journeyID: journey.id, journeyStore: journeyStore)
                }
                status = .success(journeyID: journey.id, title: title)
                lastFailedJourney = nil
                scheduleDismiss()
            } catch {
                status = .failed(
                    journeyID: journey.id,
                    title: title,
                    errorMessage: error.localizedDescription
                )
                lastFailedJourney = journey
            }
        }
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
