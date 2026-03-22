import XCTest
@testable import StreetStamps

final class MemoryEditorPresentationTests: XCTestCase {
    func test_fullScreenNotesAreaIsTallerThanSheetNotesArea() {
        XCTAssertGreaterThan(
            MemoryEditorPresentation.fullScreen.notesMinHeight,
            MemoryEditorPresentation.sheet.notesMinHeight
        )
    }

    func test_fullScreenUsesPageStyleInsteadOfCardStyle() {
        XCTAssertEqual(MemoryEditorPresentation.sheet.surfaceStyle, .card)
        XCTAssertEqual(MemoryEditorPresentation.fullScreen.surfaceStyle, .page)
    }
}
