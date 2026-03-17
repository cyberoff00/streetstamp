import Foundation

enum FriendJourneyCityIdentity {
    static func resolveCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        if let stableCityID = normalizedStableCityID(from: journey),
           cards.contains(where: { normalizeStableCityID($0.id) == stableCityID }) {
            return stableCityID
        }

        guard !cards.isEmpty else {
            return normalizedStableCityID(from: journey) ?? "Unknown|"
        }

        let exactCandidates = identityMatchCandidates(for: journey)
        if let hit = cards.first(where: { card in
            exactCandidates.contains(normalizedCardIdentity(card))
        }) {
            return hit.id
        }
        if let fuzzy = cards.first(where: {
            let normalizedName = normalizedCardIdentity($0)
            return exactCandidates.contains(where: { candidate in
                !candidate.isEmpty
                    && !normalizedName.isEmpty
                    && (candidate.contains(normalizedName) || normalizedName.contains(candidate))
            })
        }) {
            return fuzzy.id
        }
        return "Unknown|"
    }

    static func resolveCollectionKey(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        let rawCityID = resolveCityID(for: journey, cards: cards)
        return CityCollectionResolver.resolveCollectionKey(cityKey: rawCityID)
    }

    static func stableCityID(from route: JourneyRoute) -> String? {
        normalizeStableCityID(route.stableCityKey)
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
