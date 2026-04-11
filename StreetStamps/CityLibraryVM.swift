import Foundation
import MapKit
import SwiftUI
import Combine

enum CityDisplayResolver {
    static func title(
        for cityKey: String,
        fallbackTitle: String,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let localeID = locale.identifier
        if localeID.hasPrefix("en") { return fallbackTitle }
        if let translated = CityNameTranslationCache.shared.cachedName(cityKey: cityKey, localeID: localeID) {
            return translated
        }
        return fallbackTitle
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
    var parentScopeKey: String? = nil
    var availableLevelNamesEN: [String: String]? = nil
    var identityLevelRaw: String? = nil
    var isPhotoDiscovered: Bool = false
    var photoCount: Int? = nil
    var photoDateRange: String? = nil

    var allCoordinates: [CLLocationCoordinate2D] {
        let coords = journeys.flatMap { $0.allCLCoords }
        return coords.isEmpty ? (anchor.map { [$0] } ?? []) : coords
    }

    var effectiveBoundary: [CLLocationCoordinate2D]? {
        boundaryPolygon ?? bboxPolygon(for: allCoordinates)
    }

    var localizedName: String {
        return displayName ?? name
    }

    var identityLevel: CityPlacemarkResolver.CardLevel {
        identityLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) } ?? .locality
    }
}

@MainActor
final class CityLibraryVM: ObservableObject {
    @Published var cities: [City] = []
    private weak var cityCache: CityCache?
    private var networkObserver: AnyCancellable?
    private var retryTask: Task<Void, Never>?

    func load(journeyStore: JourneyStore, cityCache: CityCache) {
        self.cityCache = cityCache
        self.cities = Self.buildCities(journeyStore: journeyStore, cityCache: cityCache)
        retryTask?.cancel()
        retryTask = Task {
            await prefetchDisplayNamesDetached()
        }
        observeNetworkChanges()
    }

    /// On network path change (VPN toggle, reconnect), retry untranslated cities.
    private func observeNetworkChanges() {
        // Only subscribe once
        guard networkObserver == nil else { return }
        networkObserver = NotificationCenter.default
            .publisher(for: ReverseGeocodeService.networkPathDidChange)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.retryUntranslatedCities()
            }
    }

    private func retryUntranslatedCities() {
        let localeID = LanguagePreference.shared.effectiveLocaleIdentifier
        guard !localeID.hasPrefix("en") else { return }
        // Only retry cities whose displayName still equals the English fallback name
        let untranslated = cities.filter { $0.displayName == nil || $0.displayName == $0.name }
        guard !untranslated.isEmpty else { return }
        retryTask?.cancel()
        retryTask = Task {
            await retryPrefetchDetached(cityIDs: Set(untranslated.map(\.id)))
        }
    }

    func upsertCity(cityKey: String, journeyStore: JourneyStore, cityCache: CityCache) {
        self.cityCache = cityCache
        let trimmedKey = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only process data for this specific city key — avoids O(all_cities × all_journeys)
        // rebuild that the full buildCities would do. buildCities' merge logic (multiple
        // CachedCity entries sharing the same key) still works correctly on this subset.
        let relevantCached = cityCache.cachedCities.filter {
            $0.cityKey.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedKey
        }
        guard !relevantCached.isEmpty else {
            removeCity(cityKey: trimmedKey)
            sortCities()
            return
        }
        let relevantJourneyIDs = Set(relevantCached.flatMap { $0.journeyIds })
        let relevantJourneys = journeyStore.journeys.filter { relevantJourneyIDs.contains($0.id) }
        let nextCities = Self.buildCities(journeys: relevantJourneys, cachedCities: relevantCached)

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
            parentScopeKey: cached.parentScopeKey,
            availableLevelNamesEN: cached.availableLevelNamesEN,
            identityLevelRaw: cached.identityLevelRaw
        )
    }

    private func sortCities() {
        cities.sort {
            // Journey-derived first, then photo-discovered
            if $0.isPhotoDiscovered != $1.isPhotoDiscovered {
                return !$0.isPhotoDiscovered
            }
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
            var parentScopeKey: String?
            var identityLevelRaw: String?
            var availableLevelNamesEN: [String: String]?
            var isPhotoDiscovered: Bool
            var photoCount: Int?
            var photoDateRange: String?
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
                existing.parentScopeKey = existing.parentScopeKey ?? c.parentScopeKey
                existing.identityLevelRaw = existing.identityLevelRaw ?? c.identityLevelRaw
                existing.availableLevelNamesEN = existing.availableLevelNamesEN ?? c.availableLevelNamesEN
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
                    parentScopeKey: c.parentScopeKey,
                    identityLevelRaw: c.identityLevelRaw,
                    availableLevelNamesEN: c.availableLevelNamesEN,
                    isPhotoDiscovered: c.isPhotoDiscovered == true,
                    photoCount: c.photoCount,
                    photoDateRange: c.photoDateRange
                )
            }
        }

        var out: [City] = grouped.values.map { aggregate in
            City(
                displayName: {
                    let localeID = LanguagePreference.shared.effectiveLocaleIdentifier
                    if localeID.hasPrefix("en") { return aggregate.fallbackName }
                    return CityNameTranslationCache.shared.cachedName(cityKey: aggregate.cityKey, localeID: localeID) ?? aggregate.fallbackName
                }(),
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
                parentScopeKey: aggregate.parentScopeKey,
                availableLevelNamesEN: aggregate.availableLevelNamesEN,
                identityLevelRaw: aggregate.identityLevelRaw,
                isPhotoDiscovered: aggregate.isPhotoDiscovered,
                photoCount: aggregate.photoCount,
                photoDateRange: aggregate.photoDateRange
            )
        }

        // Sort: journey-derived first (by explorations desc), then photo-discovered (by name)
        out.sort {
            if $0.isPhotoDiscovered != $1.isPhotoDiscovered {
                return !$0.isPhotoDiscovered // journey-derived first
            }
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
        return out
    }

    // MARK: - City name localization
    /// Resolve localized city names for city cards via CityNameTranslationCache.
    /// English names are already available from CachedCity.canonicalNameEN.
    /// For non-English locales, we async-translate through the translation cache.
    /// After first pass, automatically retries failed cities once after a delay.
    private nonisolated func prefetchDisplayNamesDetached() async {
        let failedIDs = await translateCities(cityIDs: nil)
        guard !failedIDs.isEmpty, !Task.isCancelled else { return }

        // Delayed retry for cities that failed (e.g. geocoder throttle, VPN routing issue)
        try? await Task.sleep(nanoseconds: 8_000_000_000) // 8s
        guard !Task.isCancelled else { return }
        _ = await translateCities(cityIDs: failedIDs)
    }

    /// Retry translation for specific untranslated cities (called on network path change).
    private nonisolated func retryPrefetchDetached(cityIDs: Set<String>) async {
        _ = await translateCities(cityIDs: cityIDs)
    }

    /// Translate a set of cities (or all if cityIDs is nil). Returns IDs that failed.
    private nonisolated func translateCities(cityIDs: Set<String>?) async -> Set<String> {
        let snapshot: [City] = await MainActor.run { self.cities }
        let displayLocale = LanguagePreference.shared.displayLocale
        let localeID = displayLocale.identifier

        if localeID.hasPrefix("en") { return [] }

        let targets = cityIDs == nil ? snapshot : snapshot.filter { cityIDs!.contains($0.id) }
        var failed = Set<String>()

        for city in targets {
            guard !Task.isCancelled else { break }
            let level: CityPlacemarkResolver.CardLevel = await MainActor.run {
                self.cityCache?.cachedCities.first(where: { $0.cityKey == city.id })?.identityLevel ?? city.identityLevel
            }
            let translated = await CityNameTranslationCache.shared.translate(
                cityKey: city.id,
                anchor: city.anchor,
                level: level,
                locale: displayLocale
            )
            if let translated, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                        self.cities[idx].displayName = translated
                    }
                }
            } else if CityNameTranslationCache.isTranslatable(cityKey: city.id, localeID: localeID) {
                // Only count as "failed" if the city SHOULD have been translated but wasn't
                failed.insert(city.id)
            }
        }
        return failed
    }

    private nonisolated func prefetchDisplayNameDetached(cityID: String) async {
        let city: City? = await MainActor.run {
            self.cities.first(where: { $0.id == cityID })
        }
        guard let city else { return }
        let displayLocale = LanguagePreference.shared.displayLocale
        let localeID = displayLocale.identifier

        // If current locale is English, name is already correct
        if localeID.hasPrefix("en") { return }

        let level: CityPlacemarkResolver.CardLevel = await MainActor.run {
            self.cityCache?.cachedCities.first(where: { $0.cityKey == city.id })?.identityLevel ?? city.identityLevel
        }
        let translated = await CityNameTranslationCache.shared.translate(
            cityKey: city.id,
            anchor: city.anchor,
            level: level,
            locale: displayLocale
        )
        if let translated, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run {
                if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                    self.cities[idx].displayName = translated
                }
            }
        }
    }

}
