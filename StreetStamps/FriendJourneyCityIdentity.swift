import Foundation
import CoreLocation

enum FriendJourneyCityIdentity {
    private static let cacheLock = NSLock()
    private static var geocodedCityIDCache: [String: String] = [:]

    static func resolveCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        // 1. Trust stored cityID if it looks like a valid city key ("Name|ISO2")
        if let stableCityID = normalizedStableCityID(from: journey),
           looksLikeCityKey(stableCityID) {
            return stableCityID
        }

        // 2. Check geocode cache
        if let cached = cachedGeocodedCityID(for: journey.id) {
            return cached
        }

        // 3. Exact text match only (no fuzzy)
        guard !cards.isEmpty else {
            return normalizedStableCityID(from: journey) ?? "Unknown|"
        }

        let exactCandidates = identityMatchCandidates(for: journey)
        if let hit = cards.first(where: { card in
            exactCandidates.contains(normalizedCardIdentity(card))
        }) {
            return hit.id
        }

        return "Unknown|"
    }

    /// Async version: reverse geocodes from coordinates if sync resolution failed.
    static func resolvedCityIDAsync(for journey: FriendSharedJourney, cards: [FriendCityCard]) async -> String {
        let syncResult = resolveCityID(for: journey, cards: cards)
        if syncResult != "Unknown|" {
            return syncResult
        }

        // Try reverse geocode from journey coordinates
        guard let first = journey.routeCoordinates.first else {
            return syncResult
        }
        let coord = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        guard coord.isValid else { return syncResult }

        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let geocoder = CLGeocoder()
        let fixedLocale = Locale(identifier: "en_US")

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: fixedLocale)
            guard let pm = placemarks.first else { return syncResult }

            let cityName = (pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let iso2 = (pm.isoCountryCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            guard !cityName.isEmpty, iso2.count == 2 else { return syncResult }

            let cityKey = "\(cityName)|\(iso2)"
            setCachedGeocodedCityID(cityKey, for: journey.id)
            return cityKey
        } catch {
            return syncResult
        }
    }

    static func resolveCollectionKey(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        let rawCityID = resolveCityID(for: journey, cards: cards)
        return CityCollectionResolver.resolveCollectionKey(cityKey: rawCityID)
    }

    static func stableCityID(from route: JourneyRoute) -> String? {
        normalizeStableCityID(route.stableCityKey)
    }

    // MARK: - Private

    private static func looksLikeCityKey(_ value: String) -> Bool {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parts[1].trimmingCharacters(in: .whitespacesAndNewlines).count == 2
    }

    private static func cachedGeocodedCityID(for journeyID: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return geocodedCityIDCache[journeyID]
    }

    private static func setCachedGeocodedCityID(_ cityID: String, for journeyID: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        geocodedCityIDCache[journeyID] = cityID
    }

    private static func normalizedStableCityID(from journey: FriendSharedJourney) -> String? {
        normalizeStableCityID(journey.cityID)
    }

    private static func normalizeStableCityID(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizeText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    private static func normalizedCardIdentity(_ card: FriendCityCard) -> String {
        let name = normalizeText(card.name)
        if !name.isEmpty {
            return name
        }
        let keyName = normalizeText(cityName(from: card.id))
        return keyName
    }

    private static func identityMatchCandidates(for journey: FriendSharedJourney) -> [String] {
        var candidates: [String] = []

        let normalizedTitle = normalizeText(journey.title)
        if !normalizedTitle.isEmpty {
            candidates.append(normalizedTitle)
        }

        if let stableCityID = normalizedStableCityID(from: journey) {
            let normalizedKeyName = normalizeText(cityName(from: stableCityID))
            if !normalizedKeyName.isEmpty {
                candidates.append(normalizedKeyName)
            }
        }

        return Array(Set(candidates))
    }

    private static func cityName(from cityID: String) -> String {
        cityID
            .split(separator: "|", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
    }
}
