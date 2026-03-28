import Foundation

enum PostcardCityOptionsPresentation {
    static func buildOptions(
        cachedCities: [CachedCity],
        journeyCandidates: [JourneyRoute]
    ) -> [(id: String, name: String)] {
        var ordered: [(id: String, name: String)] = []

        func appendOption(id: String, name: String) {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, !trimmedName.isEmpty else { return }
            guard !ordered.contains(where: { $0.id == trimmedID }) else { return }
            ordered.append((trimmedID, trimmedName))
        }

        let cityByKey: [String: CachedCity] = {
            var map: [String: CachedCity] = [:]
            for city in cachedCities where !(city.isTemporary ?? false) {
                let id = city.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { map[id] = city }
            }
            return map
        }()

        // 1) City library entries first — use the single source of truth.
        for city in cachedCities where !(city.isTemporary ?? false) {
            let id = city.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            appendOption(id: id, name: city.displayTitle)
        }

        // 2) Journey candidates — only adds cities not already in the library.
        for journey in journeyCandidates {
            let id = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            if let city = cityByKey[id] {
                appendOption(id: id, name: city.displayTitle)
            } else {
                let keyName = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                appendOption(id: id, name: keyName.isEmpty ? journey.displayCityName : keyName)
            }
        }

        return ordered
    }
}
