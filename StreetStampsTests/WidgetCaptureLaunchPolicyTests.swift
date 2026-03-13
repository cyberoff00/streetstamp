import XCTest
@testable import StreetStamps

final class WidgetCaptureLaunchPolicyTests: XCTestCase {
    func test_shouldOpenEditorOnMapAppear_whenPendingSignalAndTrackingActive() {
        let shouldOpen = WidgetCaptureLaunchPolicy.shouldOpenEditorOnMapAppear(
            pendingWidgetCaptureSignal: 1,
            isTracking: true,
            isPaused: false
        )

        XCTAssertTrue(shouldOpen)
    }

    func test_shouldNotOpenEditorOnMapAppear_whenSignalMissing() {
        let shouldOpen = WidgetCaptureLaunchPolicy.shouldOpenEditorOnMapAppear(
            pendingWidgetCaptureSignal: 0,
            isTracking: true,
            isPaused: false
        )

        XCTAssertFalse(shouldOpen)
    }

    func test_shouldNotOpenEditorOnMapAppear_whenTrackingNotActive() {
        let shouldOpen = WidgetCaptureLaunchPolicy.shouldOpenEditorOnMapAppear(
            pendingWidgetCaptureSignal: 1,
            isTracking: false,
            isPaused: false
        )

        XCTAssertFalse(shouldOpen)
    }

    func test_shouldNotOpenEditorOnMapAppear_whenTrackingPaused() {
        let shouldOpen = WidgetCaptureLaunchPolicy.shouldOpenEditorOnMapAppear(
            pendingWidgetCaptureSignal: 1,
            isTracking: true,
            isPaused: true
        )

        XCTAssertFalse(shouldOpen)
    }
}
