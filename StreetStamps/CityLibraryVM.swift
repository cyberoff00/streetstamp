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

    var allCoordinates: [CLLocationCoordinate2D] {
        let coords = journeys.flatMap { $0.allCLCoords }
        return coords.isEmpty ? (anchor.map { [$0] } ?? []) : coords
    }

    var effectiveBoundary: [CLLocationCoordinate2D]? {
        boundaryPolygon ?? bboxPolygon(for: allCoordinates)  // ✅ 现在来自 CityMapUtils.swift
    }
}

@MainActor
final class CityLibraryVM: ObservableObject {
    @Published var cities: [City] = []

    func load(journeyStore: JourneyStore, cityCache: CityCache) {
        let journeys = journeyStore.journeys
        let byId = Dictionary(uniqueKeysWithValues: journeys.map { ($0.id, $0) })

        let cached = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }

        var out: [City] = []
        out.reserveCapacity(cached.count)

        for c in cached {
            let js = c.journeyIds.compactMap { byId[$0] }.filter { $0.isCompleted }
            let boundary = c.boundary?.map { $0.cl }
            let anchor = c.anchor?.cl

            out.append(
                City(
                    id: c.id,
                    name: c.name,
                    countryISO2: c.countryISO2,
                    journeys: js,
                    boundaryPolygon: boundary,
                    anchor: anchor,
                    explorations: c.explorations,
                    memories: c.memories,
                    thumbnailBasePath: c.thumbnailBasePath,
                    thumbnailRoutePath: c.thumbnailRoutePath
                )
            )
        }

        out.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }

        self.cities = out

        // Prefetch localized display names (city cards)
        Task.detached { [weak self] in
            guard let self else { return }
            await self.prefetchDisplayNamesDetached()
        }
    }

    // MARK: - City name localization
    /// Resolve localized city names for city cards.
    /// Keeps `name` as canonical (stable, English) while `displayName` follows the current locale.
    private nonisolated func prefetchDisplayNamesDetached() async {
        // Snapshot on MainActor
        let snapshot: [City] = await MainActor.run { self.cities }

        for city in snapshot {
            let coord = city.anchor ?? city.allCoordinates.first
            guard let coord,
                  CLLocationCoordinate2DIsValid(coord),
                  abs(coord.latitude) <= 90,
                  abs(coord.longitude) <= 180
            else { continue }

            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let key = city.id

            // 1) Use cached value first (no rate-limit hit)
            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key) {
                let t = cached.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    await MainActor.run {
                        if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                            self.cities[idx].displayName = t
                        }
                    }
                }
                continue
            }

            // 2) Fetch with rate-limit friendly pacing
            var fetched: String? = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key)

            if fetched == nil {
                // Wait a bit then try once more (ReverseGeocodeService skips when rate-limited)
                try? await Task.sleep(nanoseconds: 1_650_000_000)
                fetched = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key)
            }

            if let fetched {
                let t = fetched.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    await MainActor.run {
                        if let idx = self.cities.firstIndex(where: { $0.id == city.id }) {
                            self.cities[idx].displayName = t
                        }
                    }
                }
            }

            // Small pace to avoid spamming geocoder and to let UI stay smooth
            try? await Task.sleep(nanoseconds: 1_650_000_000)
        }
    }

}
