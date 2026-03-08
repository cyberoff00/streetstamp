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
}
