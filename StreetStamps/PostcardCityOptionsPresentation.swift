import Foundation

enum PostcardCityOptionsPresentation {
    static func buildOptions(
        cachedCities: [CachedCity],
        journeyCandidates: [JourneyRoute],
        localizedCityNamesByID: [String: String],
        locale: Locale = .current
    ) -> [(id: String, name: String)] {
        var ordered: [(id: String, name: String)] = []

        func appendOption(id: String, name: String) {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, !trimmedName.isEmpty else { return }
            guard !ordered.contains(where: { $0.id == trimmedID }) else { return }
            ordered.append((trimmedID, trimmedName))
        }

        for journey in journeyCandidates {
            let id = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prefetched = localizedCityNamesByID[id], !prefetched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendOption(id: id, name: prefetched)
                continue
            }

            let resolved = CityPlacemarkResolver.displayTitle(
                cityKey: id,
                iso2: journey.countryISO2,
                fallbackTitle: journey.displayCityName,
                locale: locale
            )
            appendOption(id: id, name: resolved)
        }

        for city in cachedCities where !(city.isTemporary ?? false) {
            let id = city.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }

            // Keep postcard city labels aligned with city-card naming rules.
            let resolved = CityPlacemarkResolver.displayTitle(
                cityKey: city.id,
                iso2: city.countryISO2,
                fallbackTitle: city.name,
                availableLevelNamesRaw: city.reservedAvailableLevelNames,
                storedAvailableLevelNamesLocaleID: city.reservedAvailableLevelNamesLocaleID,
                parentRegionKey: city.reservedParentRegionKey,
                preferredLevel: city.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: city.localizedDisplayNameByLocale,
                locale: locale
            )
            if !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendOption(id: id, name: resolved)
                continue
            }

            if let prefetched = localizedCityNamesByID[id], !prefetched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendOption(id: id, name: prefetched)
                continue
            }

            appendOption(id: id, name: city.name)
        }

        return ordered
    }
}

