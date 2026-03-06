import XCTest
@testable import StreetStamps

final class TrackTileBuilderTests: XCTestCase {
    func test_buildTiles_splitsByTileAndPreservesSourceType() {
        let events: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .passive,
                timestamp: Date(timeIntervalSince1970: 1_700_000_600),
                coordinate: CoordinateCodable(lat: 37.7753, lon: -122.4188)
            )
        ]

        let out = TrackTileBuilder.build(events: events, zoom: 10)

        XCTAssertFalse(out.tiles.isEmpty)
        XCTAssertTrue(out.tiles.values.flatMap(\ .segments).contains { $0.sourceType == .journey })
        XCTAssertTrue(out.tiles.values.flatMap(\ .segments).contains { $0.sourceType == .passive })
    }

    func test_builder_generatesLowerPointDensityForLowZoom() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [TrackRenderEvent] = (0..<24).map { index in
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: start.addingTimeInterval(Double(index)),
                coordinate: CoordinateCodable(
                    lat: 37.7749 + (Double(index) * 0.0001),
                    lon: -122.4194 + (Double(index) * 0.0001)
                )
            )
        }

        let lowZoom = TrackTileBuilder.build(events: events, zoom: 4)
        let highZoom = TrackTileBuilder.build(events: events, zoom: 14)

        let lowCount = lowZoom.tiles.values.flatMap(\.segments).flatMap(\.coordinates).count
        let highCount = highZoom.tiles.values.flatMap(\.segments).flatMap(\.coordinates).count
        XCTAssertLessThan(lowCount, highCount)
    }

    func test_builder_producesDeterministicTileKeying() {
        let event = TrackRenderEvent(
            sourceType: .journey,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
        )

        let first = TrackTileBuilder.build(events: [event], zoom: 10)
        let second = TrackTileBuilder.build(events: [event], zoom: 10)

        XCTAssertEqual(first.tiles.keys.count, 1)
        XCTAssertEqual(second.tiles.keys.count, 1)
        XCTAssertEqual(first.tiles.keys.first, TrackTileKey(z: 10, x: 163, y: 395))
        XCTAssertEqual(first.tiles.keys.first, second.tiles.keys.first)
    }

    func test_builder_keepsSeparateSegmentsWhenReenteringSameTile() {
        let events: [TrackRenderEvent] = [
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_010),
                coordinate: CoordinateCodable(lat: 37.7840, lon: -122.4090)
            ),
            TrackRenderEvent(
                sourceType: .journey,
                timestamp: Date(timeIntervalSince1970: 1_700_000_020),
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            )
        ]

        let out = TrackTileBuilder.build(events: events, zoom: 12)
        let journeySegments = out.tiles.values.flatMap(\.segments).filter { $0.sourceType == .journey }
        XCTAssertEqual(journeySegments.count, 3)
    }
}
