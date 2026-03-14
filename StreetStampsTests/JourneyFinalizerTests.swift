import XCTest
import CoreLocation
@testable import StreetStamps

final class JourneyFinalizerTests: XCTestCase {
    @MainActor
    func test_finalize_marksStationaryDriftJourneyTooShort() async throws {
        let userID = "journey-finalizer-drift-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)
        let lifelogStore = LifelogStore(paths: paths)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = JourneyRoute(
            id: "drift-only",
            startTime: start,
            endTime: start.addingTimeInterval(6 * 60 * 60),
            distance: 1_600,
            coordinates: [
                CoordinateCodable(lat: 51.50070, lon: -0.12460),
                CoordinateCodable(lat: 51.50092, lon: -0.12448),
                CoordinateCodable(lat: 51.50061, lon: -0.12473),
                CoordinateCodable(lat: 51.50076, lon: -0.12458)
            ],
            trackingMode: .daily
        )

        let finalized = await finalize(
            route: route,
            journeyStore: journeyStore,
            cityCache: cityCache,
            lifelogStore: lifelogStore
        )

        XCTAssertTrue(finalized.isTooShort)
    }

    @MainActor
    func test_finalize_keepsLegitimateMovingJourney() async throws {
        let userID = "journey-finalizer-moving-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)
        let lifelogStore = LifelogStore(paths: paths)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = JourneyRoute(
            id: "real-move",
            startTime: start,
            endTime: start.addingTimeInterval(15 * 60),
            distance: 1_600,
            coordinates: [
                CoordinateCodable(lat: 51.50070, lon: -0.12460),
                CoordinateCodable(lat: 51.50420, lon: -0.12150),
                CoordinateCodable(lat: 51.50740, lon: -0.12780)
            ],
            trackingMode: .daily
        )

        let finalized = await finalize(
            route: route,
            journeyStore: journeyStore,
            cityCache: cityCache,
            lifelogStore: lifelogStore
        )

        XCTAssertFalse(finalized.isTooShort)
    }

    @MainActor
    func test_finalize_backfillsPendingMemory_withoutBlockingJourneyCompletion() async throws {
        let userID = "journey-finalizer-memory-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)
        let lifelogStore = LifelogStore(paths: paths)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let memoryTime = start.addingTimeInterval(90)
        let route = JourneyRoute(
            id: "pending-memory",
            startTime: start,
            endTime: start.addingTimeInterval(15 * 60),
            distance: 1_600,
            coordinates: [
                CoordinateCodable(lat: 51.50070, lon: -0.12460),
                CoordinateCodable(lat: 51.50420, lon: -0.12150),
                CoordinateCodable(lat: 51.50740, lon: -0.12780)
            ],
            memories: [
                JourneyMemory(
                    id: "memory-1",
                    timestamp: memoryTime,
                    title: "Tunnel exit",
                    notes: "Signal was weak",
                    imageData: nil,
                    coordinate: (0, 0),
                    type: .memory,
                    locationStatus: .pending,
                    locationSource: .pending
                )
            ],
            trackingMode: .daily
        )

        let finalized = await withCheckedContinuation { continuation in
            JourneyFinalizer.finalize(
                route: route,
                journeyStore: journeyStore,
                cityCache: cityCache,
                lifelogStore: lifelogStore,
                source: .userConfirmedFinish,
                recordedLocations: [
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: 51.50420, longitude: -0.12150),
                        altitude: 0,
                        horizontalAccuracy: 10,
                        verticalAccuracy: 10,
                        timestamp: memoryTime.addingTimeInterval(5)
                    )
                ]
            ) { finalized in
                continuation.resume(returning: finalized)
            }
        }

        XCTAssertEqual(finalized.memories.first?.locationStatus, .fallback)
        XCTAssertEqual(finalized.memories.first?.locationSource, .trackNearestByTime)
        XCTAssertEqual(finalized.memories.first?.coordinate.0, 51.50420, accuracy: 0.0001)
        XCTAssertEqual(finalized.memories.first?.coordinate.1, -0.12150, accuracy: 0.0001)
        XCTAssertNotNil(finalized.endTime)
    }

    @MainActor
    private func finalize(
        route: JourneyRoute,
        journeyStore: JourneyStore,
        cityCache: CityCache,
        lifelogStore: LifelogStore
    ) async -> JourneyRoute {
        await withCheckedContinuation { continuation in
            JourneyFinalizer.finalize(
                route: route,
                journeyStore: journeyStore,
                cityCache: cityCache,
                lifelogStore: lifelogStore,
                source: .userConfirmedFinish
            ) { finalized in
                continuation.resume(returning: finalized)
            }
        }
    }
}
