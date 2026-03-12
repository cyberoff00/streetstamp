import XCTest
@testable import StreetStamps

final class AboutUsPresentationTests: XCTestCase {
    func test_contentUsesExpectedTitleAndLocation() {
        XCTAssertEqual(AboutUsContent.title, "关于我们")
        XCTAssertEqual(AboutUsContent.location, "伦敦")
    }

    func test_sectionsPreserveOriginalStructure() {
        let sections = AboutUsContent.sections

        XCTAssertEqual(sections.map(\.title), ["", "话外", "旅行者的需求", "赛博遛狗的故事"])
        XCTAssertEqual(sections[0].paragraphs.count, 4)
        XCTAssertEqual(sections[1].paragraphs.count, 1)
        XCTAssertEqual(sections[2].paragraphs.count, 1)
        XCTAssertEqual(sections[3].paragraphs.count, 1)
    }

    func test_storyHeadingDoesNotRepeatAsBodyCopyInPreviousSection() {
        XCTAssertFalse(
            AboutUsContent.sections[2].paragraphs.contains("赛博遛狗的故事")
        )
    }
}
