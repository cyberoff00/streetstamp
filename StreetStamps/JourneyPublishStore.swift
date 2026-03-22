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

    func publish(
        journey: JourneyRoute,
        sessionStore: UserSessionStore,
        cityCache: CityCache,
        journeyStore: JourneyStore
    ) {
        let title = journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (journey.customTitle ?? journey.displayCityName)
            : journey.displayCityName

        guard journey.visibility == .public || journey.visibility == .friendsOnly else { return }
        guard BackendConfig.isEnabled,
              sessionStore.currentAccessToken?.isEmpty == false else { return }

        dismissTask?.cancel()
        status = .sending(journeyID: journey.id, title: title)
        lastFailedJourney = journey
        lastFailedSessionStore = sessionStore
        lastFailedCityCache = cityCache
        lastFailedJourneyStore = journeyStore

        Task {
            do {
                try await JourneyCloudMigrationService.syncJourneyVisibilityChange(
                    journey: journey,
                    sessionStore: sessionStore,
                    cityCache: cityCache
                )
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
        guard let journey = lastFailedJourney,
              let sessionStore = lastFailedSessionStore,
              let cityCache = lastFailedCityCache,
              let journeyStore = lastFailedJourneyStore else { return }
        publish(
            journey: journey,
            sessionStore: sessionStore,
            cityCache: cityCache,
            journeyStore: journeyStore
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
}
