import XCTest
@testable import StreetStamps

final class JourneyEntryPreviewTextTests: XCTestCase {
    func test_make_usesJourneyCustomTitleWhenPresent() {
        let journey = JourneyRoute(
            customTitle: "Evening Train Ride",
            overallMemory: "Quiet sky over the river"
        )
        let memories = [
            JourneyMemory(
                id: "m1",
                timestamp: Date(timeIntervalSince1970: 1),
                title: "",
                notes: "Window reflections and station lights",
                imageData: nil,
                coordinate: (0, 0),
                type: .memory
            )
        ]

        let preview = JourneyEntryPreviewText.make(journey: journey, memories: memories)

        XCTAssertEqual(preview, "Evening Train Ride")
    }

    func test_make_combinesOverallMemoryAndFirstMemoryNotesWhenJourneyTitleMissing() {
        let journey = JourneyRoute(
            customTitle: "   ",
            overallMemory: "Quiet sky over the river"
        )
        let memories = [
            JourneyMemory(
                id: "m1",
                timestamp: Date(timeIntervalSince1970: 1),
                title: "",
                notes: "Window reflections and station lights",
                imageData: nil,
                coordinate: (0, 0),
                type: .memory
            )
        ]

        let preview = JourneyEntryPreviewText.make(journey: journey, memories: memories)

        XCTAssertEqual(preview, "Quiet sky over the river\nWindow reflections and station lights")
    }

    func test_make_usesOverallMemoryOnlyWhenFirstMemoryHasNoBody() {
        let journey = JourneyRoute(
            customTitle: nil,
            overallMemory: "Quiet sky over the river"
        )
        let memories = [
            JourneyMemory(
                id: "m1",
                timestamp: Date(timeIntervalSince1970: 1),
                title: "",
                notes: "   ",
                imageData: nil,
                coordinate: (0, 0),
                type: .memory
            )
        ]

        let preview = JourneyEntryPreviewText.make(journey: journey, memories: memories)

        XCTAssertEqual(preview, "Quiet sky over the river")
    }
}
