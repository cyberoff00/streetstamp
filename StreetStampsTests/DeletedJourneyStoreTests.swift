import XCTest
@testable import StreetStamps

@MainActor
final class DeletedJourneyStoreTests: XCTestCase {
    func test_discardJourney_recordsDeletedJourneyID() throws {
        let paths = StoragePath(userID: "local_deleted_store_\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let store = JourneyStore(paths: paths)
        let journey = JourneyRoute(
            id: "journey-deleted",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.6, lon: -0.13)
            ]
        )

        store.addCompletedJourney(journey)
        store.discardJourney(id: journey.id)
        store.flushPersist()

        let deletedIDs = DeletedJourneyStore.load(userID: paths.userID)
        XCTAssertTrue(deletedIDs.contains(journey.id))
    }
}
