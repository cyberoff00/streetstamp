import XCTest
@testable import StreetStamps

final class CityThumbnailDebugLoggerTests: XCTestCase {
    func test_noisyKindsRequireVerboseMode() {
        XCTAssertFalse(CityThumbnailDebugLogger.LogKind.keySame.logsByDefault)
        XCTAssertFalse(CityThumbnailDebugLogger.LogKind.memoryHit.logsByDefault)
        XCTAssertFalse(CityThumbnailDebugLogger.LogKind.cancel.logsByDefault)
        XCTAssertFalse(CityThumbnailDebugLogger.LogKind.renderComplete.logsByDefault)
    }

    func test_importantKindsLogByDefault() {
        XCTAssertTrue(CityThumbnailDebugLogger.LogKind.keyFirstSeen.logsByDefault)
        XCTAssertTrue(CityThumbnailDebugLogger.LogKind.keyChanged.logsByDefault)
        XCTAssertTrue(CityThumbnailDebugLogger.LogKind.diskHit.logsByDefault)
        XCTAssertTrue(CityThumbnailDebugLogger.LogKind.renderMiss.logsByDefault)
    }
}
