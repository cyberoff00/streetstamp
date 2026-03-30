import XCTest
@testable import StreetStamps

final class JourneyMemoryDetailExportPresentationTests: XCTestCase {
    func test_journeyDateString_zeroPadsSingleDigitDay() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 3
        components.day = 8

        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(
            JourneyMemoryDatePresentation.journeyDateString(
                for: date,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            ),
            "MAR 08, 2026"
        )
    }

    func test_normalizedCustomTitle_trimsMeaningfulTitle() {
        XCTAssertEqual(
            JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: "  Sunset Run  "),
            "Sunset Run"
        )
    }

    func test_normalizedCustomTitle_returnsNilForWhitespaceOnlyInput() {
        XCTAssertNil(JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: " \n "))
    }

    func test_exportTitle_prefersTrimmedCustomTitle() {
        XCTAssertEqual(
            JourneyMemoryDetailTitlePresentation.exportTitle(
                customTitle: "  Sunset Run  ",
                fallbackCityName: "London"
            ),
            "Sunset Run"
        )
    }

    func test_exportTitle_fallsBackToCityNameWhenCustomTitleBlank() {
        XCTAssertEqual(
            JourneyMemoryDetailTitlePresentation.exportTitle(
                customTitle: " \n ",
                fallbackCityName: "London"
            ),
            "London"
        )
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
