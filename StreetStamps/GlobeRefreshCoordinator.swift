import Foundation
import Combine

@MainActor
final class GlobeRefreshCoordinator: ObservableObject {
    enum Reason: Equatable {
        case globePageEntered
        case journeySaved
        case passiveDayRolledOver
    }

    static let shared = GlobeRefreshCoordinator()

    @Published private(set) var revision: Int = 0
    private(set) var lastReason: Reason?

    private init() {}

    func requestRefresh(reason: Reason) {
        revision &+= 1
        lastReason = reason
    }

    func resetForTesting() {
        revision = 0
        lastReason = nil
    }
}

struct GlobeRefreshGate {
    private(set) var isRefreshing = false
    private(set) var needsAnotherPass = false

    mutating func startOrQueue() -> Bool {
        if isRefreshing {
            needsAnotherPass = true
            return false
        }
        isRefreshing = true
        needsAnotherPass = false
        return true
    }

    mutating func finish() -> Bool {
        let shouldRefreshAgain = needsAnotherPass
        isRefreshing = false
        needsAnotherPass = false
        return shouldRefreshAgain
    }
}

enum GlobeRouteResolver {
    static func shouldFetchUnifiedSegments(tileSegments: [TrackTileSegment]) -> Bool {
        tileSegments.isEmpty
    }

    static func resolve(
        externalJourneys: [JourneyRoute]?,
        summaryJourneys: [JourneyRoute],
        segments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun] = [],
        countryISO2: String?
    ) -> [JourneyRoute] {
        let routes = TrackRenderAdapter.globeJourneys(
            from: segments,
            passiveCountryRuns: passiveCountryRuns,
            countryISO2: countryISO2
        )
        if !routes.isEmpty {
            return routes
        }

        if let externalJourneys, !externalJourneys.isEmpty {
            return externalJourneys
        }

        return summaryJourneys
    }
}
