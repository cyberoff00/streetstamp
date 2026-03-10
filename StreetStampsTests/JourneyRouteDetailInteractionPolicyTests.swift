import XCTest
@testable import StreetStamps

final class JourneyRouteDetailInteractionPolicyTests: XCTestCase {
    func test_memoryTap_usesReadOnlyDetailWhenJourneyIsReadOnly() {
        XCTAssertEqual(
            JourneyRouteDetailInteractionPolicy.destinationForMemoryTap(isReadOnly: true),
            .viewMemory
        )
    }

    func test_memoryTap_usesEditorWhenJourneyIsEditable() {
        XCTAssertEqual(
            JourneyRouteDetailInteractionPolicy.destinationForMemoryTap(isReadOnly: false),
            .editMemory
        )
    }
}
