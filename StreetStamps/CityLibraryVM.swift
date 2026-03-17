import Foundation
import MapKit
import SwiftUI
import Combine   // ✅ 必须：ObservableObject / @Published

enum CityCollectionResolver {
    fileprivate struct Mapping: Decodable {
        var cityToCollection: [String: String] = [:]
        var collectionTitles: [String: String] = [:]
    }

    private static var testingMapping = Mapping()
    private static let bundleMapping: Mapping = loadBundleMapping()

    static func resolveCollectionKey(cityKey: String) -> String {
        let trimmed = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return activeMapping.cityToCollection[trimmed] ?? trimmed
    }

    static func resolveCollectionKey(for journey: JourneyRoute) -> String {
        resolveCollectionKey(cityKey: journey.startCityKey ?? journey.cityKey)
    }

    static func resolveCollectionKey(
        for journey: JourneyRoute,
        cachedCitiesByKey: [String: CachedCity]
    ) -> String {
        let rawKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawKey.isEmpty else { return rawKey }
        if let cached = cachedCitiesByKey[rawKey] {
            return resolveCollectionKey(for: cached)
        }
        return resolveCollectionKey(cityKey: rawKey)
    }

    static func resolveCollectionKey(
        cityKey: String,
        selectedDisplayLevelRaw: String?,
        availableLevelNamesRaw: [String: String]?,
        iso2: String?
    ) -> String {
        let trimmed = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Use raw identity (cityKey) to query mapping, not dynamic key based on user selection
        return activeMapping.cityToCollection[trimmed] ?? trimmed
    }

    static func resolveCollectionKey(for cachedCity: CachedCity) -> String {
        resolveCollectionKey(
            cityKey: cachedCity.cityKey,
            selectedDisplayLevelRaw: cachedCity.selectedDisplayLevelRaw,
            availableLevelNamesRaw: cachedCity.availableLevelNames,
            iso2: cachedCity.countryISO2
        )
    }

    static func configuredTitle(for collectionKey: String) -> String? {
        let trimmed = collectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return activeMapping.collectionTitles[trimmed]
    }

    static func setTestingMappings(
        cityToCollection: [String: String],
        collectionTitles: [String: String]
    ) {
        testingMapping = Mapping(cityToCollection: cityToCollection, collectionTitles: collectionTitles)
    }

    static func resetForTesting() {
        testingMapping = Mapping()
    }

    private static var activeMapping: Mapping {
        var merged = bundleMapping
        if !testingMapping.cityToCollection.isEmpty {
            merged.cityToCollection.merge(testingMapping.cityToCollection) { _, new in new }
        }
        if !testingMapping.collectionTitles.isEmpty {
            merged.collectionTitles.merge(testingMapping.collectionTitles) { _, new in new }
        }
        return merged
    }

    private static func loadBundleMapping() -> Mapping {
        guard let url = Bundle.main.url(forResource: "CityCollectionMapping", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Mapping.self, from: data) else {
            return Mapping()
        }
        return decoded
    }

    private static func iso2FromKey(_ key: String) -> String? {
        key
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .first
            .map(String.init)
    }
}

enum CityDisplayResolver {
    static func title(
        for collectionKey: String,
        fallbackTitle: String,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let trimmedKey = collectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return fallbackTitle }
        let configured = CityCollectionResolver.configuredTitle(for: trimmedKey) ?? fallbackTitle
        return CityDisplayTitlePresentation.title(
            cityKey: trimmedKey,
            iso2: iso2(from: trimmedKey),
            fallbackTitle: configured,
            locale: locale
        )
    }

    static func iso2(from collectionKey: String) -> String? {
        collectionKey
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
            preferredLevel: city.selectedDisplayLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
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
        let collectionKey = cityCache.cachedCities
            .first(where: { $0.id == cityKey && !($0.isTemporary ?? false) })
            .map(CityCollectionResolver.resolveCollectionKey(for:))
            ?? CityCollectionResolver.resolveCollectionKey(cityKey: cityKey)
        let nextCities = Self.buildCities(
            journeys: journeyStore.journeys,
            cachedCities: cityCache.cachedCities
        )

        if let next = nextCities.first(where: { $0.id == collectionKey }) {
            if let idx = cities.firstIndex(where: { $0.id == collectionKey }) {
                cities[idx] = next
            } else {
                cities.append(next)
            }
        } else {
            removeCity(cityKey: collectionKey)
        }
        sortCities()
        Task {
            await prefetchDisplayNameDetached(cityID: collectionKey)
        }
    }

    func removeCity(cityKey: String) {
        cities.removeAll { $0.id == cityKey }
    }

    private func makeCity(from cached: CachedCity, journeysById: [String: JourneyRoute]) -> City {
        let js = cached.journeyIds.compactMap { journeysById[$0] }.filter { $0.isCompleted }
        return City(
            displayName: CityPlacemarkResolver.displayTitle(for: cached, locale: LanguagePreference.shared.displayLocale),
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
        let byId = Dictionary(uniqueKeysWithValues: journeys.map { ($0.id, $0) })
        let cached = cachedCities.filter { !($0.isTemporary ?? false) }

        struct Aggregate {
            let collectionKey: String
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
        }

        var grouped: [String: Aggregate] = [:]
        for c in cached {
            let collectionKey = CityCollectionResolver.resolveCollectionKey(for: c)
            let resolvedJourneys = c.journeyIds.compactMap { byId[$0] }.filter { $0.isCompleted }
            let fallbackName = CityCollectionResolver.configuredTitle(for: collectionKey) ?? c.name

            if var existing = grouped[collectionKey] {
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
                grouped[collectionKey] = existing
            } else {
                grouped[collectionKey] = Aggregate(
                    collectionKey: collectionKey,
                    fallbackName: fallbackName,
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
                    localizedDisplayNameByLocale: c.localizedDisplayNameByLocale
                )
            }
        }

        var out: [City] = grouped.values.map { aggregate in
            City(
                displayName: CityDisplayResolver.title(
                    for: aggregate.collectionKey,
                    fallbackTitle: aggregate.fallbackName,
                    locale: LanguagePreference.shared.displayLocale
                ),
                id: aggregate.collectionKey,
                name: aggregate.fallbackName,
                countryISO2: aggregate.countryISO2 ?? CityDisplayResolver.iso2(from: aggregate.collectionKey),
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

            let unified = CityPlacemarkResolver.displayTitle(
                cityKey: city.id,
                iso2: city.countryISO2,
                fallbackTitle: city.localizedName,
                availableLevelNamesRaw: city.availableLevelNames,
                storedAvailableLevelNamesLocaleID: city.availableLevelNamesLocaleID,
                parentRegionKey: city.parentScopeKey,
                preferredLevel: city.selectedDisplayLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: city.localizedDisplayNameByLocale,
                locale: displayLocale
            )
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
            var fetched: String? = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.parentScopeKey)

            if fetched == nil {
                // Wait a bit then try once more (ReverseGeocodeService skips when rate-limited)
                try? await Task.sleep(nanoseconds: 1_650_000_000)
                fetched = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.parentScopeKey)
            }

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

            // Small pace to avoid spamming geocoder and to let UI stay smooth
            try? await Task.sleep(nanoseconds: 1_650_000_000)
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
        let unified = CityPlacemarkResolver.displayTitle(
            cityKey: city.id,
            iso2: city.countryISO2,
            fallbackTitle: city.displayName ?? city.name,
            availableLevelNamesRaw: city.availableLevelNames,
            storedAvailableLevelNamesLocaleID: city.availableLevelNamesLocaleID,
            parentRegionKey: city.parentScopeKey,
            preferredLevel: city.selectedDisplayLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
            localizedDisplayNameByLocale: city.localizedDisplayNameByLocale,
            locale: displayLocale
        )
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
