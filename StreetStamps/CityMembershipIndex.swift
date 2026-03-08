import Foundation

struct CityMembershipEntry: Codable, Equatable {
    let cityKey: String
    var cityName: String
    var countryISO2: String?
    var journeyIDs: [String]
    var memories: Int

    var explorations: Int { journeyIDs.count }

    init(
        cityKey: String,
        cityName: String,
        countryISO2: String?,
        journeyIDs: [String] = [],
        memories: Int = 0
    ) {
        self.cityKey = cityKey
        self.cityName = cityName
        self.countryISO2 = CityMembershipEntry.normalizeISO(countryISO2)
        self.journeyIDs = journeyIDs
        self.memories = memories
    }

    mutating func applyRemoval(journeyID: String, memories removedMemories: Int) {
        journeyIDs.removeAll(where: { $0 == journeyID })
        memories = max(0, memories - removedMemories)
    }

    mutating func applyAddition(_ contribution: CityMembershipContribution) {
        if !journeyIDs.contains(contribution.journeyID) {
            journeyIDs.append(contribution.journeyID)
        }
        cityName = contribution.cityName
        countryISO2 = contribution.countryISO2
        memories += contribution.memories
    }

    var isEmpty: Bool {
        journeyIDs.isEmpty
    }

    private static func normalizeISO(_ iso: String?) -> String? {
        let trimmed = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CityMembershipIndex: Codable, Equatable {
    var entries: [String: CityMembershipEntry] = [:]

    init(entries: [String: CityMembershipEntry] = [:]) {
        self.entries = entries
    }

    mutating func applyJourneyMutation(oldJourney: JourneyRoute?, newJourney: JourneyRoute?) {
        if let oldContribution = CityMembershipContribution(journey: oldJourney) {
            var existing = entries[oldContribution.cityKey] ?? CityMembershipEntry(
                cityKey: oldContribution.cityKey,
                cityName: oldContribution.cityName,
                countryISO2: oldContribution.countryISO2
            )
            existing.applyRemoval(journeyID: oldContribution.journeyID, memories: oldContribution.memories)
            if existing.isEmpty {
                entries.removeValue(forKey: oldContribution.cityKey)
            } else {
                entries[oldContribution.cityKey] = existing
            }
        }

        if let newContribution = CityMembershipContribution(journey: newJourney) {
            var existing = entries[newContribution.cityKey] ?? CityMembershipEntry(
                cityKey: newContribution.cityKey,
                cityName: newContribution.cityName,
                countryISO2: newContribution.countryISO2
            )
            existing.applyAddition(newContribution)
            entries[newContribution.cityKey] = existing
        }
    }
}

struct CityMembershipContribution: Equatable {
    let cityKey: String
    let cityName: String
    let countryISO2: String?
    let journeyID: String
    let memories: Int

    init?(journey: JourneyRoute?) {
        guard let journey, journey.isCompleted else { return nil }

        let rawKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let cityKey = rawKey.isEmpty ? journey.canonicalCityKeyFallback : rawKey
        guard !cityKey.isEmpty else { return nil }

        let split = CityMembershipContribution.splitCityKey(cityKey)
        let fallbackName = journey.displayCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = split.name.isEmpty ? fallbackName : split.name
        guard !finalName.isEmpty else { return nil }

        self.cityKey = cityKey
        self.cityName = finalName
        self.countryISO2 = split.iso.isEmpty ? CityMembershipContribution.normalizeISO(journey.countryISO2) : split.iso
        self.journeyID = journey.id
        self.memories = journey.memoryCount
    }

    private static func splitCityKey(_ cityKey: String) -> (name: String, iso: String) {
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let iso = parts.dropFirst().first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        return (name, iso)
    }

    private static func normalizeISO(_ iso: String?) -> String? {
        let trimmed = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
