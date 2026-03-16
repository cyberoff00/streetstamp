import XCTest
@testable import StreetStamps

final class JourneyMemoryDetailExportPresentationTests: XCTestCase {
    func test_normalizedCustomTitle_trimsMeaningfulTitle() {
        XCTAssertEqual(
            JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: "  Sunset Run  "),
            "Sunset Run"
        )
    }

    func test_normalizedCustomTitle_returnsNilForWhitespaceOnlyInput() {
        XCTAssertNil(JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: " \n "))
    }

    func test_shouldShowOverallMemory_isFalseForNilOrWhitespace() {
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: nil, overallMemoryImagePaths: []).shouldShowOverallMemory)
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: "", overallMemoryImagePaths: []).shouldShowOverallMemory)
        XCTAssertFalse(JourneyMemoryDetailExportPresentation(overallMemory: "  \n ", overallMemoryImagePaths: []).shouldShowOverallMemory)
    }

    func test_shouldShowOverallMemory_isTrueForTrimmedContent() {
        let presentation = JourneyMemoryDetailExportPresentation(
            overallMemory: "  很开心，风很舒服。  ",
            overallMemoryImagePaths: []
        )

        XCTAssertTrue(presentation.shouldShowOverallMemory)
        XCTAssertEqual(presentation.overallMemoryText, "很开心，风很舒服。")
    }

    func test_shouldShowOverallMemory_isTrueWhenOnlyPhotosExist() {
        let presentation = JourneyMemoryDetailExportPresentation(
            overallMemory: " \n ",
            overallMemoryImagePaths: ["overall-1.jpg"]
        )

        XCTAssertTrue(presentation.shouldShowOverallMemory)
    }
}
