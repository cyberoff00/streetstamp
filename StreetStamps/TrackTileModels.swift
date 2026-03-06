import Foundation

enum TrackSourceType: String, Codable, CaseIterable, Hashable {
    case journey
    case passive
}

struct TrackRenderEvent: Codable, Equatable {
    let sourceType: TrackSourceType
    let timestamp: Date
    let coordinate: CoordinateCodable
}

struct TrackTileKey: Hashable, Codable, Equatable {
    let z: Int
    let x: Int
    let y: Int
}

struct TrackTileSegment: Codable, Equatable {
    let sourceType: TrackSourceType
    let coordinates: [CoordinateCodable]
    let startTimestamp: Date
    let endTimestamp: Date

    init(
        sourceType: TrackSourceType,
        coordinates: [CoordinateCodable],
        startTimestamp: Date = .distantPast,
        endTimestamp: Date = .distantPast
    ) {
        self.sourceType = sourceType
        self.coordinates = coordinates
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case sourceType
        case coordinates
        case startTimestamp
        case endTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceType = try container.decode(TrackSourceType.self, forKey: .sourceType)
        coordinates = try container.decode([CoordinateCodable].self, forKey: .coordinates)
        startTimestamp = try container.decodeIfPresent(Date.self, forKey: .startTimestamp) ?? .distantPast
        endTimestamp = try container.decodeIfPresent(Date.self, forKey: .endTimestamp) ?? startTimestamp
    }
}

struct TrackTileBucket: Codable, Equatable {
    var segments: [TrackTileSegment]
}

struct TrackTileBuildOutput: Codable, Equatable {
    var tiles: [TrackTileKey: TrackTileBucket]
}
