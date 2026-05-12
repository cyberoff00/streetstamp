import XCTest
@testable import StreetStamps

final class RemoteImageLoadTimeoutTests: XCTestCase {
    func test_withOptionalTimeout_returnsValueWhenOperationFinishesInTime() async {
        let value = await RemoteImageLoadTimeout.withOptionalTimeout(
            nanoseconds: 200_000_000
        ) {
            try? await Task.sleep(nanoseconds: 10_000_000)
            return 42
        }

        XCTAssertEqual(value, 42)
    }

    func test_withOptionalTimeout_returnsNilWhenOperationExceedsDeadline() async {
        let value = await RemoteImageLoadTimeout.withOptionalTimeout(
            nanoseconds: 10_000_000
        ) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return 42
        }

        XCTAssertNil(value)
    }
}
