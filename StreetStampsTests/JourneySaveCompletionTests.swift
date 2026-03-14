import XCTest
@testable import StreetStamps

final class JourneySaveCompletionTests: XCTestCase {
    @MainActor
    func test_persistFinalizedJourney_updatesInMemoryVisibilityImmediately() throws {
        let userID = "journey-save-completion-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = JourneyStore(paths: paths)

        let baseJourney = JourneyRoute(
            id: "journey-1",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            distance: 3_500,
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.51, lon: -0.11)
            ],
            visibility: .private
        )
        store.addCompletedJourney(baseJourney)

        var finalized = baseJourney
        finalized.visibility = .friendsOnly

        JourneySaveCompletion.persistFinalizedJourney(finalized, in: store)

        XCTAssertEqual(store.journeys.first?.id, finalized.id)
        XCTAssertEqual(store.journeys.first?.visibility, .friendsOnly)
    }
}
