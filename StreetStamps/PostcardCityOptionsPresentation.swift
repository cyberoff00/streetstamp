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

        // Build a lookup so journey candidates can reuse CachedCity locale data.
        let cityByCollectionKey: [String: CachedCity] = {
            var map: [String: CachedCity] = [:]
            for city in cachedCities where !(city.isTemporary ?? false) {
                let id = CityCollectionResolver.resolveCollectionKey(cityKey: city.id.trimmingCharacters(in: .whitespacesAndNewlines))
                if !id.isEmpty { map[id] = city }
            }
            return map
        }()

        func resolveName(id: String, city: CachedCity) -> String {
            if let prefetched = localizedCityNamesByID[id], !prefetched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return prefetched
            }
            let resolved = CityPlacemarkResolver.displayTitle(for: city, locale: locale)
            if !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return resolved
            }
            let keyName = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return keyName.isEmpty ? city.name : keyName
        }

        // 1) City library entries first — highest-quality locale-aware names.
        for city in cachedCities where !(city.isTemporary ?? false) {
            let id = CityCollectionResolver.resolveCollectionKey(cityKey: city.id.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !id.isEmpty else { continue }
            appendOption(id: id, name: resolveName(id: id, city: city))
        }

        // 2) Journey candidates — only adds cities not already covered by the library.
        //    Still uses CachedCity data when available for name consistency.
        for journey in journeyCandidates {
            let rawID = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = CityCollectionResolver.resolveCollectionKey(cityKey: rawID)
            guard !id.isEmpty else { continue }
            if let city = cityByCollectionKey[id] {
                appendOption(id: id, name: resolveName(id: id, city: city))
            } else {
                let keyName = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                appendOption(id: id, name: keyName.isEmpty ? journey.displayCityName : keyName)
            }
        }

        return ordered
    }
}
