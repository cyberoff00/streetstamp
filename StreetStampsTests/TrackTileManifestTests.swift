import XCTest
@testable import StreetStamps

final class TrackTileManifestTests: XCTestCase {
    func test_decodesLegacyManifest_withoutNewRevisionMetadataFields() throws {
        let json = """
        {
          "schemaVersion": 4,
          "zoom": 10,
          "journeyRevision": 2,
          "passiveRevision": 3,
          "updatedAt": "2026-03-07T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decoder.decode(
            TrackTileManifest.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(manifest.schemaVersion, 4)
        XCTAssertEqual(manifest.zoom, 10)
        XCTAssertEqual(manifest.journeyRevision, 2)
        XCTAssertEqual(manifest.passiveRevision, 3)
        XCTAssertEqual(manifest.journeyEventCount, 0)
        XCTAssertEqual(manifest.passiveEventCount, 0)
        XCTAssertNil(manifest.journeyLastEventTimestamp)
        XCTAssertNil(manifest.passiveLastEventTimestamp)
        XCTAssertNil(manifest.journeyLastEventCoord)
        XCTAssertNil(manifest.passiveLastEventCoord)
        XCTAssertNil(manifest.journeyTailEvents)
        XCTAssertNil(manifest.passiveTailEvents)
    }
}
