import XCTest
@testable import StreetStamps

final class MapFinishPolicyTests: XCTestCase {
    func test_shouldWarnBeforeFinish_whenPendingMemoryExists() {
        let journey = JourneyRoute(
            memories: [
                JourneyMemory(
                    id: "pending",
                    timestamp: Date(),
                    title: "Draft",
                    notes: "",
                    imageData: nil,
                    coordinate: (0, 0),
                    type: .memory,
                    locationStatus: .pending,
                    locationSource: .pending
                )
            ]
        )

        XCTAssertTrue(MapFinishPolicy.shouldWarnBeforeFinish(journey: journey))
    }

    func test_shouldNotWarnBeforeFinish_whenAllMemoriesStable() {
        let journey = JourneyRoute(
            memories: [
                JourneyMemory(
                    id: "resolved",
                    timestamp: Date(),
                    title: "Pinned",
                    notes: "",
                    imageData: nil,
                    coordinate: (51.5, -0.12),
                    type: .memory,
                    locationStatus: .resolved,
                    locationSource: .liveGPS
                )
            ]
        )

        XCTAssertFalse(MapFinishPolicy.shouldWarnBeforeFinish(journey: journey))
    }

    func test_dropPendingMemoriesBeforeFinish_removesOnlyPendingMemories() {
        let pending = JourneyMemory(
            id: "pending",
            timestamp: Date(),
            title: "Pending",
            notes: "",
            imageData: nil,
            coordinate: (0, 0),
            type: .memory,
            locationStatus: .pending,
            locationSource: .pending
        )
        let resolved = JourneyMemory(
            id: "resolved",
            timestamp: Date(),
            title: "Resolved",
            notes: "",
            imageData: nil,
            coordinate: (51.5, -0.12),
            type: .memory,
            locationStatus: .resolved,
            locationSource: .liveGPS
        )
        let journey = JourneyRoute(memories: [pending, resolved])

        let filtered = MapFinishPolicy.dropPendingMemoriesBeforeFinish(journey)

        XCTAssertEqual(filtered.memories.map(\.id), ["resolved"])
    }
}
