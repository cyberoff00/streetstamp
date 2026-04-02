import XCTest

final class SharingCardSourceTests: XCTestCase {
    func test_sharingCardRendersWheneverJourneyHasAtLeastOneCoordinate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/SharingCard.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("private var canRenderCard: Bool { journey.coordinates.count >= 1 && !journey.isTooShort }"))
    }

    func test_hideLandmarksUsesBlurOverlay() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharingCardSource = try String(contentsOf: root.appendingPathComponent("StreetStamps/SharingCard.swift"))
        let journeyMemorySource = try String(contentsOf: root.appendingPathComponent("StreetStamps/JourneyMemoryNew.swift"))

        XCTAssertTrue(sharingCardSource.contains("func mapPrivacyBlurred"), "Sharing card should define a blur helper for privacy rendering.")
        XCTAssertTrue(sharingCardSource.contains("hideLandmarks"), "Sharing card should support hideLandmarks parameter.")
        XCTAssertTrue(journeyMemorySource.contains("mapPrivacyBlurred(base"), "Journey thumbnails should blur the map when hideLandmarks is enabled.")
    }
}
