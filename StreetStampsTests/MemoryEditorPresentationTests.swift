import XCTest
import UIKit
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

    func test_newMedia_requiresEditing_beforePersistence() {
        XCTAssertTrue(MemoryEditorMediaPolicy.requiresEditingBeforeSave)
    }

    func test_pickerLaunch_dismissesTextInput_beforeSchedulingPresentation() {
        var events: [String] = []
        var scheduledAction: (() -> Void)?

        PhotoInputPresentationPolicy.launchPicker(
            dismissTextInput: {
                events.append("dismiss")
            },
            schedulePresentation: { action in
                events.append("schedule")
                scheduledAction = action
            },
            presentPicker: {
                events.append("present")
            }
        )

        XCTAssertEqual(events, ["dismiss", "schedule"])
        XCTAssertNotNil(scheduledAction)

        scheduledAction?()

        XCTAssertEqual(events, ["dismiss", "schedule", "present"])
    }

    func test_editorPresentation_waitsForModalTransition_whenImagesPending() {
        var capturedDelay: TimeInterval?
        var didPresentEditor = false

        PhotoInputPresentationPolicy.scheduleEditorPresentationIfNeeded(
            pendingImages: [UIImage()],
            schedulePresentation: { delay, action in
                capturedDelay = delay
                action()
            },
            presentEditor: {
                didPresentEditor = true
            }
        )

        XCTAssertEqual(capturedDelay, PhotoInputPresentationPolicy.editorLaunchDelay)
        XCTAssertTrue(didPresentEditor)
    }

    func test_editorPresentation_skipsScheduling_whenNoImagesPending() {
        var didSchedule = false

        PhotoInputPresentationPolicy.scheduleEditorPresentationIfNeeded(
            pendingImages: [],
            schedulePresentation: { _, _ in
                didSchedule = true
            },
            presentEditor: {}
        )

        XCTAssertFalse(didSchedule)
    }
}
