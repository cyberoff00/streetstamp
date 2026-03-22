import XCTest
@testable import StreetStamps

final class JourneyPublishDirtyPolicyTests: XCTestCase {

    private func makeMemory(id: String = "m1", title: String = "T", notes: String = "N") -> JourneyMemory {
        JourneyMemory(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_710_000_000),
            title: title,
            notes: notes,
            imageData: nil,
            imagePaths: [],
            cityKey: "tokyo_jp",
            cityName: "Tokyo",
            coordinate: (35.68, 139.76),
            type: .memory
        )
    }

    // MARK: - Private journeys never prompt

    func test_private_journey_always_savesLocal_even_with_changes() {
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .private,
            snapshotMemories: [makeMemory(title: "Old")],
            draftMemories: [makeMemory(title: "New")],
            snapshotTitle: "Old Title",
            draftTitle: "New Title",
            snapshotOverallMemory: "old",
            draftOverallMemory: "new",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: ["img.jpg"]
        )
        XCTAssertEqual(action, .saveLocal)
    }

    // MARK: - Shared journey with no changes -> saveLocal

    func test_friendsOnly_noChanges_savesLocal() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "Title",
            draftTitle: "Title",
            snapshotOverallMemory: "Overall",
            draftOverallMemory: "Overall",
            snapshotOverallMemoryImagePaths: ["a.jpg"],
            draftOverallMemoryImagePaths: ["a.jpg"]
        )
        XCTAssertEqual(action, .saveLocal)
    }

    // MARK: - Shared journey with changes -> promptRepublish

    func test_friendsOnly_titleChanged_promptsRepublish() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "Old",
            draftTitle: "New",
            snapshotOverallMemory: "",
            draftOverallMemory: "",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: []
        )
        XCTAssertEqual(action, .promptRepublish)
    }

    func test_public_overallMemoryChanged_promptsRepublish() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .public,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "T",
            draftTitle: "T",
            snapshotOverallMemory: "old notes",
            draftOverallMemory: "new notes",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: []
        )
        XCTAssertEqual(action, .promptRepublish)
    }

    func test_friendsOnly_memoryEdited_promptsRepublish() {
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [makeMemory(title: "Before")],
            draftMemories: [makeMemory(title: "After")],
            snapshotTitle: "T",
            draftTitle: "T",
            snapshotOverallMemory: "",
            draftOverallMemory: "",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: []
        )
        XCTAssertEqual(action, .promptRepublish)
    }

    func test_friendsOnly_overallImagePathsChanged_promptsRepublish() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "T",
            draftTitle: "T",
            snapshotOverallMemory: "same",
            draftOverallMemory: "same",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: ["new.jpg"]
        )
        XCTAssertEqual(action, .promptRepublish)
    }

    // MARK: - Whitespace-only differences are not real changes

    func test_whitespace_only_title_diff_savesLocal() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "Title",
            draftTitle: "  Title  ",
            snapshotOverallMemory: "note",
            draftOverallMemory: "note",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: []
        )
        XCTAssertEqual(action, .saveLocal)
    }

    func test_whitespace_only_overallMemory_diff_savesLocal() {
        let mem = makeMemory()
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: .friendsOnly,
            snapshotMemories: [mem],
            draftMemories: [mem],
            snapshotTitle: "T",
            draftTitle: "T",
            snapshotOverallMemory: "hello",
            draftOverallMemory: "\nhello\n",
            snapshotOverallMemoryImagePaths: [],
            draftOverallMemoryImagePaths: []
        )
        XCTAssertEqual(action, .saveLocal)
    }
}
