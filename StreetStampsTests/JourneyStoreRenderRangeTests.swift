import XCTest
@testable import StreetStamps

final class JourneyStoreRenderRangeTests: XCTestCase {
    func test_resolveRenderRange_returnsNilWhenNoTimeSignals() {
        var journey = JourneyRoute()
        journey.coordinates = [
            CoordinateCodable(lat: 1, lon: 1),
            CoordinateCodable(lat: 2, lon: 2)
        ]

        XCTAssertNil(JourneyStore.resolveRenderRange(for: journey))
    }

    func test_resolveRenderRange_fallsBackToMemoryTimestamps() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_120)

        var journey = JourneyRoute()
        journey.coordinates = [
            CoordinateCodable(lat: 1, lon: 1),
            CoordinateCodable(lat: 2, lon: 2)
        ]
        journey.memories = [
            JourneyMemory(
                id: "m1",
                timestamp: t2,
                title: "b",
                notes: "",
                imageData: nil,
                coordinate: (0, 0),
                type: .memory
            ),
            JourneyMemory(
                id: "m2",
                timestamp: t1,
                title: "a",
                notes: "",
                imageData: nil,
                coordinate: (0, 0),
                type: .memory
            )
        ]

        let range = JourneyStore.resolveRenderRange(for: journey)
        XCTAssertEqual(range?.0, t1)
        XCTAssertEqual(range?.1, t2)
    }
}
