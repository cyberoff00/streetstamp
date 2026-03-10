import XCTest
@testable import StreetStamps

final class JourneyRouteCodableTests: XCTestCase {
    func test_overallMemoryImagePaths_survive_codable_roundTrip() throws {
        let route = JourneyRoute(
            distance: 3_500,
            memories: [],
            overallMemory: "Windy bridge walk",
            overallMemoryImagePaths: ["overall-1.jpg", "overall-2.jpg"]
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(JourneyRoute.self, from: data)

        XCTAssertEqual(decoded.overallMemory, "Windy bridge walk")
        XCTAssertEqual(decoded.overallMemoryImagePaths, ["overall-1.jpg", "overall-2.jpg"])
    }

    func test_hasJourneyMemoryListContent_isTrueForTrimmedOverallMemoryWithoutJourneyMemories() {
        let route = JourneyRoute(
            memories: [],
            overallMemory: "  Quiet sunset by the river  "
        )

        XCTAssertTrue(route.hasJourneyMemoryListContent)
    }

    func test_hasJourneyMemoryListContent_isFalseWhenNoJourneyMemoriesAndOverallMemoryIsBlank() {
        let route = JourneyRoute(
            memories: [],
            overallMemory: " \n "
        )

        XCTAssertFalse(route.hasJourneyMemoryListContent)
    }
}
