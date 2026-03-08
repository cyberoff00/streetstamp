import XCTest
@testable import StreetStamps

final class JourneyMemoryDetailExportPresentationTests: XCTestCase {
    func test_shouldShowOverallMemory_isFalseForNilOrWhitespace() {
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: nil).shouldShowOverallMemory)
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: "").shouldShowOverallMemory)
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: "  \n ").shouldShowOverallMemory)
    }

    func test_shouldShowOverallMemory_isTrueForTrimmedContent() {
        let presentation = JourneyMemoryDetailExportPresentation(overallMemory: "  很开心，风很舒服。  ")

        XCTAssertTrue(presentation.shouldShowOverallMemory)
        XCTAssertEqual(presentation.overallMemoryText, "很开心，风很舒服。")
    }
}
