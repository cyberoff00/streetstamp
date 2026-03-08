import Foundation

enum TrackSourceType: String, Codable, CaseIterable, Hashable, Sendable {
    case journey
    case passive
}

struct TrackRenderEvent: Codable, Equatable, Sendable {
    let sourceType: TrackSourceType
    let timestamp: Date
    let coordinate: CoordinateCodable
}

struct TrackTileKey: Hashable, Codable, Equatable, Sendable {
    let z: Int
    let x: Int
    let y: Int
}

struct TrackTileSegment: Codable, Equatable, Sendable {
    let id: String
    let sourceType: TrackSourceType
    let coordinates: [CoordinateCodable]
    let startTimestamp: Date
    let endTimestamp: Date

    init(
        id: String = UUID().uuidString,
        sourceType: TrackSourceType,
        coordinates: [CoordinateCodable],
        startTimestamp: Date = .distantPast,
        endTimestamp: Date = .distantPast
    ) {
        self.id = id
        self.sourceType = sourceType
        self.coordinates = coordinates
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceType
        case coordinates
        case startTimestamp
        case endTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceType = try container.decode(TrackSourceType.self, forKey: .sourceType)
        coordinates = try container.decode([CoordinateCodable].self, forKey: .coordinates)
        startTimestamp = try container.decodeIfPresent(Date.self, forKey: .startTimestamp) ?? .distantPast
        endTimestamp = try container.decodeIfPresent(Date.self, forKey: .endTimestamp) ?? startTimestamp
    }
}

struct TrackTileBucket: Codable, Equatable, Sendable {
    var segments: [TrackTileSegment]
}

struct TrackTileBuildOutput: Codable, Equatable, Sendable {
    var tiles: [TrackTileKey: TrackTileBucket]
}
