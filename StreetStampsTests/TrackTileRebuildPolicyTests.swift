import XCTest
@testable import StreetStamps

final class TrackTileRebuildPolicyTests: XCTestCase {
    func test_shouldRebuild_onlyForLifelogTab() {
        XCTAssertTrue(TrackTileRebuildPolicy.shouldRebuild(for: .lifelog))
        XCTAssertFalse(TrackTileRebuildPolicy.shouldRebuild(for: .start))
        XCTAssertFalse(TrackTileRebuildPolicy.shouldRebuild(for: .friends))
        XCTAssertFalse(TrackTileRebuildPolicy.shouldRebuild(for: .cities))
        XCTAssertFalse(TrackTileRebuildPolicy.shouldRebuild(for: .memory))
    }
}
