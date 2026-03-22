import XCTest

final class SharingCardSourceTests: XCTestCase {
    func test_sharingCardRendersWheneverJourneyHasAtLeastOneCoordinate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/SharingCard.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("private var canRenderCard: Bool { journey.coordinates.count >= 1 }"))
        XCTAssertFalse(source.contains("journey.coordinates.count >= 1 && !journey.isTooShort"))
    }
}
