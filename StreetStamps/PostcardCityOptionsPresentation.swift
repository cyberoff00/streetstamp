import Foundation

enum PostcardCityOptionsPresentation {
    static func buildOptions(
        cachedCities: [CachedCity],
        journeyCandidates: [JourneyRoute],
        localizedCityNamesByID: [String: String],
        locale: Locale = LanguagePreference.shared.displayLocale
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
            let rawID = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = CityCollectionResolver.resolveCollectionKey(cityKey: rawID)
            if let prefetched = localizedCityNamesByID[id], !prefetched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendOption(id: id, name: prefetched)
                continue
            }

            let resolved = CityDisplayResolver.title(
                for: id,
                fallbackTitle: journey.displayCityName,
                locale: locale
            )
            appendOption(id: id, name: resolved)
        }

        for city in cachedCities where !(city.isTemporary ?? false) {
            let id = CityCollectionResolver.resolveCollectionKey(cityKey: city.id.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !id.isEmpty else { continue }

            // Keep postcard city labels aligned with collection-key naming rules.
            let resolved = CityDisplayResolver.title(
                for: id,
                fallbackTitle: CityCollectionResolver.configuredTitle(for: id) ?? city.name,
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
