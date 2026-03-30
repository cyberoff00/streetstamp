import Foundation

struct JourneyMemoryDetailDestination: Identifiable, Hashable {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    let cityName: String
    let countryName: String
    let readOnly: Bool
    let friendLoadout: RobotLoadout?

    var id: String { journey.id }

    func hash(into hasher: inout Hasher) { hasher.combine(journey.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.journey.id == rhs.journey.id }
}
