import XCTest
@testable import StreetStamps

final class JourneyMemoryDetailDraftStoreTests: XCTestCase {
    func test_detailDraft_roundTripsOverallMemoryFields() throws {
        let draft = JourneyMemoryDetailDraft(
            memories: [],
            focusedMemoryID: "memory-1",
            journeyTitle: "  Sunset Loop  ",
            overallMemory: "  River breeze  ",
            overallMemoryImagePaths: ["overall-1.jpg", "overall-2.jpg"]
        )

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(JourneyMemoryDetailDraft.self, from: data)

        XCTAssertEqual(decoded.focusedMemoryID, "memory-1")
        XCTAssertEqual(decoded.journeyTitle, "  Sunset Loop  ")
        XCTAssertEqual(decoded.overallMemory, "  River breeze  ")
        XCTAssertEqual(decoded.overallMemoryImagePaths, ["overall-1.jpg", "overall-2.jpg"])
    }
}
