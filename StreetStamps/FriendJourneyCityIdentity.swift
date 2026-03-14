import Foundation

enum FriendJourneyCityIdentity {
    static func resolveCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        if let stableCityID = normalizedStableCityID(from: journey) {
            return stableCityID
        }
        guard !cards.isEmpty else { return "Unknown|" }

        let normalizedTitle = normalizeText(journey.title)
        if let hit = cards.first(where: { normalizeText($0.name) == normalizedTitle }) {
            return hit.id
        }
        if let fuzzy = cards.first(where: {
            let normalizedName = normalizeText($0.name)
            return !normalizedName.isEmpty
                && !normalizedTitle.isEmpty
                && (normalizedTitle.contains(normalizedName) || normalizedName.contains(normalizedTitle))
        }) {
            return fuzzy.id
        }
        return "Unknown|"
    }

    static func stableCityID(from route: JourneyRoute) -> String? {
        normalizeStableCityID(route.startCityKey ?? route.cityKey)
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
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
