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

struct GlobePreviewSnapshot {
    let routes: [JourneyRoute]
    let visitedCountries: [String]
}

// MARK: - Globe Data Cache

/// Caches the fully-resolved Globe output (routes + visited countries) keyed
/// by the upstream data revisions. When the user re-opens Globe and data
/// hasn't changed, the entire resolve + passiveCountryRuns pipeline is skipped.
@MainActor
final class GlobeDataCache {
    static let shared = GlobeDataCache()

    private struct CacheKey: Equatable {
        let journeyRevision: Int
        let passiveRevision: Int
        let tileRefreshRevision: Int
    }

    private var key: CacheKey?
    private var routes: [JourneyRoute] = []
    private var countries: [String] = []

    private init() {}

    func get(
        journeyRevision: Int,
        passiveRevision: Int,
        tileRefreshRevision: Int
    ) -> (routes: [JourneyRoute], countries: [String])? {
        let k = CacheKey(
            journeyRevision: journeyRevision,
            passiveRevision: passiveRevision,
            tileRefreshRevision: tileRefreshRevision
        )
        guard key == k, !routes.isEmpty else { return nil }
        return (routes, countries)
    }

    func store(
        journeyRevision: Int,
        passiveRevision: Int,
        tileRefreshRevision: Int,
        routes: [JourneyRoute],
        countries: [String]
    ) {
        key = CacheKey(
            journeyRevision: journeyRevision,
            passiveRevision: passiveRevision,
            tileRefreshRevision: tileRefreshRevision
        )
        self.routes = routes
        self.countries = countries
    }

    func invalidate() {
        key = nil
        routes = []
        countries = []
    }
}

enum GlobeRouteResolver {
    static func shouldFetchUnifiedSegments(tileSegments: [TrackTileSegment]) -> Bool {
        tileSegments.isEmpty
    }

    static func previewSnapshot(
        externalJourneys: [JourneyRoute]?,
        summaryJourneys: [JourneyRoute],
        segments: [TrackTileSegment],
        countryISO2: String?,
        cityISO2: [String]
    ) -> GlobePreviewSnapshot {
        let routes = resolve(
            externalJourneys: externalJourneys,
            summaryJourneys: summaryJourneys,
            segments: segments,
            passiveCountryRuns: [],
            countryISO2: countryISO2
        )
        let countries = resolveVisitedCountries(routes: routes, cityISO2: cityISO2)
        return GlobePreviewSnapshot(routes: routes, visitedCountries: countries)
    }

    static func resolveVisitedCountries(routes: [JourneyRoute], cityISO2: [String]) -> [String] {
        var set = Set<String>()
        for j in routes {
            if let iso = j.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               iso.count == 2 {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.startCityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.cityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.endCityKey) {
                set.insert(iso)
            }
        }

        for iso in cityISO2 {
            set.insert(iso)
        }
        return Array(set).sorted()
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

    private static func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard let raw = parts.last else { return nil }
        let iso = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
    }
}
