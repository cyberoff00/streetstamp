import Foundation
import MapKit
import SwiftUI
import Combine   // ✅ 必须：ObservableObject / @Published

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
    var reservedLevelRaw: String? = nil
    var reservedParentRegionKey: String? = nil
    var reservedAvailableLevelNames: [String: String]? = nil
    var reservedAvailableLevelNamesLocaleID: String? = nil
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
        if let displayName,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let localized = localizedDisplayNameByLocale?[Locale.current.identifier]?
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
        locale: Locale = .current
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
            availableLevelNamesRaw: city.reservedAvailableLevelNames,
            storedAvailableLevelNamesLocaleID: city.reservedAvailableLevelNamesLocaleID,
            parentRegionKey: city.reservedParentRegionKey,
            preferredLevel: city.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
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
        let byId = Dictionary(uniqueKeysWithValues: journeyStore.journeys.map { ($0.id, $0) })
        guard let cached = cityCache.cachedCities.first(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) else {
            removeCity(cityKey: cityKey)
            return
        }

        var next = makeCity(from: cached, journeysById: byId)
        if let idx = cities.firstIndex(where: { $0.id == cityKey }) {
            cities[idx] = next
        } else {
            cities.append(next)
        }
        sortCities()
        Task {
            await prefetchDisplayNameDetached(cityID: cityKey)
        }
    }

    func removeCity(cityKey: String) {
        cities.removeAll { $0.id == cityKey }
    }

    private func makeCity(from cached: CachedCity, journeysById: [String: JourneyRoute]) -> City {
        let js = cached.journeyIds.compactMap { journeysById[$0] }.filter { $0.isCompleted }
        return City(
            displayName: CityPlacemarkResolver.displayTitle(for: cached, locale: .current),
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
            reservedLevelRaw: cached.reservedLevelRaw,
            reservedParentRegionKey: cached.reservedParentRegionKey,
            reservedAvailableLevelNames: cached.reservedAvailableLevelNames,
            reservedAvailableLevelNamesLocaleID: cached.reservedAvailableLevelNamesLocaleID,
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

        var out: [City] = []
        out.reserveCapacity(cached.count)
        for c in cached {
            out.append(
                City(
                    displayName: CityPlacemarkResolver.displayTitle(for: c, locale: .current),
                    id: c.id,
                    name: c.name,
                    countryISO2: c.countryISO2,
                    journeys: c.journeyIds.compactMap { byId[$0] }.filter { $0.isCompleted },
                    boundaryPolygon: c.boundary?.map { $0.cl },
                    anchor: c.anchor?.cl,
                    explorations: c.explorations,
                    memories: c.memories,
                    thumbnailBasePath: c.thumbnailBasePath,
                    thumbnailRoutePath: c.thumbnailRoutePath,
                    reservedLevelRaw: c.reservedLevelRaw,
                    reservedParentRegionKey: c.reservedParentRegionKey,
                    reservedAvailableLevelNames: c.reservedAvailableLevelNames,
                    reservedAvailableLevelNamesLocaleID: c.reservedAvailableLevelNamesLocaleID,
                    localizedDisplayNameByLocale: c.localizedDisplayNameByLocale
                )
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
                availableLevelNamesRaw: city.reservedAvailableLevelNames,
                storedAvailableLevelNamesLocaleID: city.reservedAvailableLevelNamesLocaleID,
                parentRegionKey: city.reservedParentRegionKey,
                preferredLevel: city.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: city.localizedDisplayNameByLocale,
                locale: .current
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
            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.reservedParentRegionKey) {
                let t = Self.normalizedPrefetchedDisplayTitle(
                    for: city,
                    candidateLocalizedTitle: cached,
                    locale: .current
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    CityLocalizationDebugLogger.log(
                        "cityCardPrefetch",
                        "cityKey=\(city.id) locale=\(Locale.current.identifier) source=cachedDisplayTitle candidate=\(cached) resolved=\(t)"
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
            var fetched: String? = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.reservedParentRegionKey)

            if fetched == nil {
                // Wait a bit then try once more (ReverseGeocodeService skips when rate-limited)
                try? await Task.sleep(nanoseconds: 1_650_000_000)
                fetched = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.reservedParentRegionKey)
            }

            if let fetched {
                let t = Self.normalizedPrefetchedDisplayTitle(
                    for: city,
                    candidateLocalizedTitle: fetched,
                    locale: .current
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    CityLocalizationDebugLogger.log(
                        "cityCardPrefetch",
                        "cityKey=\(city.id) locale=\(Locale.current.identifier) source=displayTitle candidate=\(fetched) resolved=\(t)"
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
                self.cityCache?.updateLocalizedDisplayNames(localizedUpdates, locale: .current)
            }
        }
    }

    private nonisolated func prefetchDisplayNameDetached(cityID: String) async {
        let city: City? = await MainActor.run {
            self.cities.first(where: { $0.id == cityID })
        }
        guard let city else { return }

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
            availableLevelNamesRaw: city.reservedAvailableLevelNames,
            storedAvailableLevelNamesLocaleID: city.reservedAvailableLevelNamesLocaleID,
            parentRegionKey: city.reservedParentRegionKey,
            preferredLevel: city.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
            localizedDisplayNameByLocale: city.localizedDisplayNameByLocale,
            locale: .current
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

        if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.reservedParentRegionKey) {
            let t = Self.normalizedPrefetchedDisplayTitle(
                for: city,
                candidateLocalizedTitle: cached,
                locale: .current
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                CityLocalizationDebugLogger.log(
                    "cityCardPrefetch",
                    "cityKey=\(city.id) locale=\(Locale.current.identifier) source=cachedDisplayTitle.single candidate=\(cached) resolved=\(t)"
                )
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                        self.cities[idx].displayName = t
                    }
                    self.cityCache?.updateLocalizedDisplayName(cityKey: key, locale: .current, displayName: t)
                }
            }
            return
        }

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let fetched = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.reservedParentRegionKey) {
            let t = Self.normalizedPrefetchedDisplayTitle(
                for: city,
                candidateLocalizedTitle: fetched,
                locale: .current
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                CityLocalizationDebugLogger.log(
                    "cityCardPrefetch",
                    "cityKey=\(city.id) locale=\(Locale.current.identifier) source=displayTitle.single candidate=\(fetched) resolved=\(t)"
                )
                await MainActor.run {
                    if let idx = self.cities.firstIndex(where: { $0.id == cityID }) {
                        self.cities[idx].displayName = t
                    }
                    self.cityCache?.updateLocalizedDisplayName(cityKey: key, locale: .current, displayName: t)
                }
            }
        }
    }

}
