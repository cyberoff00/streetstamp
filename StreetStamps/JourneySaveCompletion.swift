import Foundation

enum JourneySaveCompletion {
    @MainActor
    static func persistFinalizedJourney(_ journey: JourneyRoute, in store: JourneyStore) {
        store.addCompletedJourney(journey)
    }
}
