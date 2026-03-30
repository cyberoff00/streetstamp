import Foundation
import MapKit
import SwiftUI
import Combine   // ✅ 必须：ObservableObject / @Published

enum CityDisplayResolver {
    static func title(
        for cityKey: String,
        fallbackTitle: String,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let trimmedKey = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return fallbackTitle }
        return CityDisplayTitlePresentation.title(
            cityKey: trimmedKey,
            iso2: iso2(from: trimmedKey),
            fallbackTitle: fallbackTitle,
            locale: locale
        )
    }

    static func iso2(from cityKey: String) -> String? {
        cityKey
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .first
            .map(String.init)
    }
}

struct City: Identifiable {
    /// UI display name (localized, from reverse geocode). Falls back to `name`.
    var displayName: String? = nil
    let id: String
    let name: String
    let countryISO2: String?
    var journeys: [JourneyRoute]

    var boundaryPolygon: [CLLocationCoordinate2D]?
    var anchor: CLLocationCoordinate2D?

    var explorations: Int
    var memories: Int

    var thumbnailBasePath: String?
    var thumbnailRoutePath: String?
    var sourceCityKeys: [String] = []
    var identityLevelRaw: String? = nil
    var selectedDisplayLevelRaw: String? = nil
    var parentScopeKey: String? = nil
    var availableLevelNames: [String: String]? = nil
    var availableLevelNamesLocaleID: String? = nil
    var localizedDisplayNameByLocale: [String: String]? = nil

    var allCoordinates: [CLLocationCoordinate2D] {
        let coords = journeys.flatMap { $0.allCLCoords }
        return coords.isEmpty ? (anchor.map { [$0] } ?? []) : coords
    }

    var effectiveBoundary: [CLLocationCoordinate2D]? {
        boundaryPolygon ?? bboxPolygon(for: allCoordinates)  // ✅ 现在来自 CityMapUtils.swift
    }

    /// Best localized display name for the current locale.
    /// Priority: displayName → localizedDisplayNameByLocale → name
    /// `displayName` is already normalized through `CityPlacemarkResolver.displayTitle`,
    /// so it should win over any stale persisted localized cache.
    var localizedName: String {
        let localeID = LanguagePreference.shared.effectiveLocaleIdentifier
        if let displayName,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let localized = localizedDisplayNameByLocale?[localeID]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }
        return displayName ?? name
    }
}

@MainActor
final class CityLibraryVM: ObservableObject {
    @Published var cities: [City] = []
    private weak var cityCache: CityCache?

    nonisolated static func normalizedPrefetchedDisplayTitle(
        for city: City,
        candidateLocalizedTitle: String?,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let trimmedCandidate = candidateLocalizedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localeID = locale.identifier
        var localizedMap = city.localizedDisplayNameByLocale ?? [:]
        if let trimmedCandidate, !trimmedCandidate.isEmpty {
            localizedMap[localeID] = trimmedCandidate
        }

        return CityPlacemarkResolver.displayTitle(
            cityKey: city.id,
            iso2: city.countryISO2,
            fallbackTitle: city.displayName ?? city.name,
            availableLevelNamesRaw: city.availableLevelNames,
            storedAvailableLevelNamesLocaleID: city.availableLevelNamesLocaleID,
            parentRegionKey: city.parentScopeKey,
            preferredLevel: nil,
            localizedDisplayNameByLocale: localizedMap,
            locale: locale
        )
    }

    func load(journeyStore: JourneyStore, cityCache: CityCache) {
        self.cityCache = cityCache
        self.cities = Self.buildCities(journeyStore: journeyStore, cityCache: cityCache)
        Task {
            await prefetchDisplayNamesDetached()
        }
    }

    func upsertCity(cityKey: String, journeyStore: JourneyStore, cityCache: CityCache) {
        self.cityCache = cityCache
        let trimmedKey = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextCities = Self.buildCities(
            journeys: journeyStore.journeys,
            cachedCities: cityCache.cachedCities
        )

        if let next = nextCities.first(where: { $0.id == trimmedKey }) {
            if let idx = cities.firstIndex(where: { $0.id == trimmedKey }) {
                cities[idx] = next
            } else {
                cities.append(next)
            }
        } else {
            removeCity(cityKey: trimmedKey)
        }
        sortCities()
        Task {
            await prefetchDisplayNameDetached(cityID: trimmedKey)
        }
    }

    func removeCity(cityKey: String) {
        cities.removeAll { $0.id == cityKey }
    }

    private func makeCity(from cached: CachedCity, journeysById: [String: JourneyRoute]) -> City {
        let js = cached.journeyIds.compactMap { journeysById[$0] }.filter { $0.isCompleted }
        return City(
            displayName: cached.displayTitle,
            id: cached.id,
            name: cached.name,
            countryISO2: cached.countryISO2,
            journeys: js,
            boundaryPolygon: cached.boundary?.map { $0.cl },
            anchor: cached.anchor?.cl,
            explorations: cached.explorations,
            memories: cached.memories,
            thumbnailBasePath: cached.thumbnailBasePath,
            thumbnailRoutePath: cached.thumbnailRoutePath,
            sourceCityKeys: [cached.cityKey],
            identityLevelRaw: cached.identityLevelRaw,
            selectedDisplayLevelRaw: cached.selectedDisplayLevelRaw,
            parentScopeKey: cached.parentScopeKey,
            availableLevelNames: cached.availableLevelNames,
            availableLevelNamesLocaleID: cached.availableLevelNamesLocaleID,
            localizedDisplayNameByLocale: cached.localizedDisplayNameByLocale
        )
    }

    private func sortCities() {
        cities.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
    }

    static func buildCities(journeyStore: JourneyStore, cityCache: CityCache) -> [City] {
        buildCities(journeys: journeyStore.journeys, cachedCities: cityCache.cachedCities)
    }

    /// Nonisolated overload that takes value-type snapshots so it can run off
    /// the main actor without crossing isolation boundaries.
    nonisolated static func buildCities(
        journeys: [JourneyRoute],
        cachedCities: [CachedCity]
    ) -> [City] {
        let byId = Dictionary(journeys.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let cached = cachedCities.filter { !($0.isTemporary ?? false) }

        struct Aggregate {
            let cityKey: String
            var fallbackName: String
            var countryISO2: String?
            var sourceCityKeys: [String]
            var journeys: [JourneyRoute]
            var boundaryPolygon: [CLLocationCoordinate2D]?
            var anchor: CLLocationCoordinate2D?
            var explorations: Int
            var memories: Int
            var thumbnailBasePath: String?
            var thumbnailRoutePath: String?
            var identityLevelRaw: String?
            var selectedDisplayLevelRaw: String?
            var parentScopeKey: String?
            var availableLevelNames: [String: String]?
            var availableLevelNamesLocaleID: String?
            var localizedDisplayNameByLocale: [String: String]?
            var resolvedDisplayName: String?
            var resolvedDisplayNameLocaleID: String?
        }

        var grouped: [String: Aggregate] = [:]
        for c in cached {
            let key = c.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedJourneys = c.journeyIds.compactMap { byId[$0] }.filter { $0.isCompleted }

            if var existing = grouped[key] {
                let existingIDs = Set(existing.journeys.map(\.id))
                let appended = resolvedJourneys.filter { !existingIDs.contains($0.id) }
                existing.journeys.append(contentsOf: appended)
                if !existing.sourceCityKeys.contains(c.cityKey) {
                    existing.sourceCityKeys.append(c.cityKey)
                }
                existing.explorations += c.explorations
                existing.memories += c.memories
                existing.countryISO2 = existing.countryISO2 ?? c.countryISO2
                existing.boundaryPolygon = existing.boundaryPolygon ?? c.boundary?.map { $0.cl }
                existing.anchor = existing.anchor ?? c.anchor?.cl
                existing.thumbnailBasePath = existing.thumbnailBasePath ?? c.thumbnailBasePath
                existing.thumbnailRoutePath = existing.thumbnailRoutePath ?? c.thumbnailRoutePath
                existing.identityLevelRaw = existing.identityLevelRaw ?? c.identityLevelRaw
                existing.selectedDisplayLevelRaw = existing.selectedDisplayLevelRaw ?? c.selectedDisplayLevelRaw
                existing.parentScopeKey = existing.parentScopeKey ?? c.parentScopeKey
                existing.availableLevelNames = existing.availableLevelNames ?? c.availableLevelNames
                existing.availableLevelNamesLocaleID = existing.availableLevelNamesLocaleID ?? c.availableLevelNamesLocaleID
                existing.localizedDisplayNameByLocale = existing.localizedDisplayNameByLocale ?? c.localizedDisplayNameByLocale
                existing.resolvedDisplayName = existing.resolvedDisplayName ?? c.resolvedDisplayName
                existing.resolvedDisplayNameLocaleID = existing.resolvedDisplayNameLocaleID ?? c.resolvedDisplayNameLocaleID
                grouped[key] = existing
            } else {
                grouped[key] = Aggregate(
                    cityKey: key,
                    fallbackName: c.name,
                    countryISO2: c.countryISO2,
                    sourceCityKeys: [c.cityKey],
                    journeys: resolvedJourneys,
                    boundaryPolygon: c.boundary?.map { $0.cl },
                    anchor: c.anchor?.cl,
                    explorations: c.explorations,
                    memories: c.memories,
                    thumbnailBasePath: c.thumbnailBasePath,
                    thumbnailRoutePath: c.thumbnailRoutePath,
                    identityLevelRaw: c.identityLevelRaw,
                    selectedDisplayLevelRaw: c.selectedDisplayLevelRaw,
                    parentScopeKey: c.parentScopeKey,
                    availableLevelNames: c.availableLevelNames,
                    availableLevelNamesLocaleID: c.availableLevelNamesLocaleID,
                    localizedDisplayNameByLocale: c.localizedDisplayNameByLocale,
                    resolvedDisplayName: c.resolvedDisplayName,
                    resolvedDisplayNameLocaleID: c.resolvedDisplayNameLocaleID
                )
            }
        }

        var out: [City] = grouped.values.map { aggregate in
            let currentLocaleID = LanguagePreference.shared.effectiveLocaleIdentifier
            let resolvedName: String = {
                if let resolved = aggregate.resolvedDisplayName,
                   !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   aggregate.resolvedDisplayNameLocaleID == currentLocaleID {
                    return resolved
                }
                return aggregate.fallbackName
            }()
            return City(
                displayName: resolvedName,
                id: aggregate.cityKey,
                name: aggregate.fallbackName,
                countryISO2: aggregate.countryISO2 ?? CityDisplayResolver.iso2(from: aggregate.cityKey),
                journeys: aggregate.journeys,
                boundaryPolygon: aggregate.boundaryPolygon,
                anchor: aggregate.anchor,
                explorations: aggregate.explorations,
                memories: aggregate.memories,
                thumbnailBasePath: aggregate.thumbnailBasePath,
                thumbnailRoutePath: aggregate.thumbnailRoutePath,
                sourceCityKeys: aggregate.sourceCityKeys.sorted(),
                identityLevelRaw: aggregate.identityLevelRaw,
                selectedDisplayLevelRaw: aggregate.selectedDisplayLevelRaw,
                parentScopeKey: aggregate.parentScopeKey,
                availableLevelNames: aggregate.availableLevelNames,
                availableLevelNamesLocaleID: aggregate.availableLevelNamesLocaleID,
                localizedDisplayNameByLocale: aggregate.localizedDisplayNameByLocale
            )
        }

        out.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
        return out
    }

    // MARK: - City name localization
    /// Resolve localized city names for city cards.
    /// Keeps `name` as canonical (stable, English) while `displayName` follows the current locale.
    private nonisolated func prefetchDisplayNamesDetached() async {
        // Snapshot on MainActor
        let snapshot: [City] = await MainActor.run { self.cities }
        var localizedUpdates: [(cityKey: String, displayName: String)] = []

        for city in snapshot {
            let displayLocale = LanguagePreference.shared.displayLocale
            let coord = city.anchor ?? city.allCoordinates.first
            guard let coord,
                  CLLocationCoordinate2DIsValid(coord),
                  abs(coord.latitude) <= 90,
                  abs(coord.longitude) <= 180
            else { continue }

            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let key = city.id

            // Use resolvedDisplayName from CachedCity as immediate display value.
            let cached = await MainActor.run {
                self.cityCache?.cachedCities.first(where: { $0.id == city.id && !($0.isTemporary ?? false) })
            }
            let unified = cached?.displayTitle ?? city.localizedName
            if !unified.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                        self.cities[idx].displayName = unified
                    }
                }
            }

            if ["HK", "MO", "TW"].contains((city.countryISO2 ?? "").uppercased()) {
                continue
            }

            // 1) Use cached value first (no rate-limit hit)
            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.parentScopeKey) {
                let t = Self.normalizedPrefetchedDisplayTitle(
                    for: city,
                    candidateLocalizedTitle: cached,
                    locale: displayLocale
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    CityLocalizationDebugLogger.log(
                        "cityCardPrefetch",
                        "cityKey=\(city.id) locale=\(displayLocale.identifier) source=cachedDisplayTitle candidate=\(cached) resolved=\(t)"
                    )
                    await MainActor.run {
                        if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                            self.cities[idx].displayName = t
                        }
                    }
                    localizedUpdates.append((cityKey: key, displayName: t))
                }
                continue
            }

            // 2) Fetch with rate-limit friendly pacing
            let fetched = await ReverseGeocodeService.shared.displayTitleWithRetry(for: loc, cityKey: key, parentRegionKey: city.parentScopeKey)

            if let fetched {
                let t = Self.normalizedPrefetchedDisplayTitle(
                    for: city,
                    candidateLocalizedTitle: fetched,
                    locale: displayLocale
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    CityLocalizationDebugLogger.log(
                        "cityCardPrefetch",
                        "cityKey=\(city.id) locale=\(displayLocale.identifier) source=displayTitle candidate=\(fetched) resolved=\(t)"
                    )
                    await MainActor.run {
                        if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                            self.cities[idx].displayName = t
                        }
                    }
                    localizedUpdates.append((cityKey: key, displayName: t))
                }
            }

        }

        // Batch-persist localized names to CityCache for cold-start access
        if !localizedUpdates.isEmpty {
            await MainActor.run {
                self.cityCache?.updateLocalizedDisplayNames(localizedUpdates, locale: LanguagePreference.shared.displayLocale)
            }
        }
    }

    private nonisolated func prefetchDisplayNameDetached(cityID: String) async {
        let city: City? = await MainActor.run {
            self.cities.first(where: { $0.id == cityID })
        }
        guard let city else { return }
        let displayLocale = LanguagePreference.shared.displayLocale

        let coord = city.anchor ?? city.allCoordinates.first
        guard let coord,
              CLLocationCoordinate2DIsValid(coord),
              abs(coord.latitude) <= 90,
              abs(coord.longitude) <= 180
        else { return }

        let key = city.id
        let cached = await MainActor.run {
            self.cityCache?.cachedCities.first(where: { $0.id == key && !($0.isTemporary ?? false) })
        }
        let unified = cached?.displayTitle ?? city.displayName ?? city.name
        if !unified.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run {
                if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                    self.cities[idx].displayName = unified
                }
            }
        }

        if ["HK", "MO", "TW"].contains((city.countryISO2 ?? "").uppercased()) {
            return
        }

        if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.parentScopeKey) {
            let t = Self.normalizedPrefetchedDisplayTitle(
                for: city,
                candidateLocalizedTitle: cached,
                locale: displayLocale
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                CityLocalizationDebugLogger.log(
                    "cityCardPrefetch",
                    "cityKey=\(city.id) locale=\(displayLocale.identifier) source=cachedDisplayTitle.single candidate=\(cached) resolved=\(t)"
                )
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                        self.cities[idx].displayName = t
                    }
                    self.cityCache?.updateLocalizedDisplayName(cityKey: key, locale: displayLocale, displayName: t)
                }
            }
            return
        }

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let fetched = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.parentScopeKey) {
            let t = Self.normalizedPrefetchedDisplayTitle(
                for: city,
                candidateLocalizedTitle: fetched,
                locale: displayLocale
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                CityLocalizationDebugLogger.log(
                    "cityCardPrefetch",
                    "cityKey=\(city.id) locale=\(displayLocale.identifier) source=displayTitle.single candidate=\(fetched) resolved=\(t)"
                )
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                        self.cities[idx].displayName = t
                    }
                    self.cityCache?.updateLocalizedDisplayName(cityKey: key, locale: displayLocale, displayName: t)
                }
            }
        }
    }

}
