import Foundation

struct TrackTileManifest: Codable, Equatable {
    var schemaVersion: Int = 1
    var zoom: Int
    var journeyRevision: Int
    var passiveRevision: Int
    var journeyEventCount: Int = 0
    var passiveEventCount: Int = 0
    var journeyLastEventTimestamp: Date?
    var passiveLastEventTimestamp: Date?
    var journeyLastEventCoord: CoordinateCodable?
    var passiveLastEventCoord: CoordinateCodable?
    var updatedAt: Date
}

struct TrackTileViewport: Equatable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double
}
