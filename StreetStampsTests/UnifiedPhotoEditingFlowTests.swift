import XCTest
import UIKit
@testable import StreetStamps

final class UnifiedPhotoEditingFlowTests: XCTestCase {
    func test_queueCompletion_keepsEditedAndSkippedItems_only() {
        let first = UIImage()
        let second = UIImage()
        let third = UIImage()
        let editedFirst = UIImage()

        var state = PhotoEditingQueueState(items: [
            .init(id: "1", original: first),
            .init(id: "2", original: second),
            .init(id: "3", original: third),
        ])

        state.completeCurrent(with: editedFirst)
        state.skipCurrent()
        state.discardCurrent()

        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.finalizedItems.count, 2)
        XCTAssertTrue(state.finalizedItems[0] === editedFirst)
        XCTAssertTrue(state.finalizedItems[1] === second)
    }

    func test_primaryActionTitle_usesDoneAll_forLastItem() {
        let state = PhotoEditingQueueState(items: [
            .init(id: "last", original: UIImage())
        ])

        XCTAssertEqual(state.primaryActionTitle, "Done All")
    }

    func test_newMemoryBootstrap_prefersPreloadedImages_overGenericDraft() {
        let draft = MemoryDraft(
            title: "stale",
            notes: "stale",
            imagePaths: [],
            mirrorSelfie: true
        )

        let state = MemoryEditorBootstrapState.make(
            draft: draft,
            existing: nil,
            preloadedImagePaths: ["incoming.jpg"]
        )

        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.notes, "")
        XCTAssertEqual(state.imagePaths, ["incoming.jpg"])
        XCTAssertEqual(state.remoteImageURLs, [])
        XCTAssertFalse(state.mirrorSelfie)
    }

    func test_existingMemoryBootstrap_stillUsesSavedDraft() {
        let existing = JourneyMemory(
            id: "memory-1",
            timestamp: Date(timeIntervalSince1970: 123),
            title: "old",
            notes: "old",
            imageData: nil,
            imagePaths: ["old.jpg"],
            remoteImageURLs: ["https://example.com/old.jpg"],
            cityKey: nil,
            cityName: nil,
            coordinate: (0, 0),
            type: .memory,
            locationStatus: .pending,
            locationSource: .pending
        )
        let draft = MemoryDraft(
            title: "draft title",
            notes: "draft notes",
            imagePaths: ["draft.jpg"],
            mirrorSelfie: true
        )

        let state = MemoryEditorBootstrapState.make(
            draft: draft,
            existing: existing,
            preloadedImagePaths: ["incoming.jpg"]
        )

        XCTAssertEqual(state.title, "draft title")
        XCTAssertEqual(state.notes, "draft notes")
        XCTAssertEqual(state.imagePaths, ["draft.jpg"])
        XCTAssertEqual(state.remoteImageURLs, ["https://example.com/old.jpg"])
        XCTAssertTrue(state.mirrorSelfie)
    }
}
