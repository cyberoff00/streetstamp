import Foundation

struct TrackTileManifest: Codable, Equatable, Sendable {
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
    var journeyTailEvents: [TrackRenderEvent]?
    var passiveTailEvents: [TrackRenderEvent]?
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case zoom
        case journeyRevision
        case passiveRevision
        case journeyEventCount
        case passiveEventCount
        case journeyLastEventTimestamp
        case passiveLastEventTimestamp
        case journeyLastEventCoord
        case passiveLastEventCoord
        case journeyTailEvents
        case passiveTailEvents
        case updatedAt
    }

    init(
        schemaVersion: Int = 1,
        zoom: Int,
        journeyRevision: Int,
        passiveRevision: Int,
        journeyEventCount: Int = 0,
        passiveEventCount: Int = 0,
        journeyLastEventTimestamp: Date? = nil,
        passiveLastEventTimestamp: Date? = nil,
        journeyLastEventCoord: CoordinateCodable? = nil,
        passiveLastEventCoord: CoordinateCodable? = nil,
        journeyTailEvents: [TrackRenderEvent]? = nil,
        passiveTailEvents: [TrackRenderEvent]? = nil,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.zoom = zoom
        self.journeyRevision = journeyRevision
        self.passiveRevision = passiveRevision
        self.journeyEventCount = journeyEventCount
        self.passiveEventCount = passiveEventCount
        self.journeyLastEventTimestamp = journeyLastEventTimestamp
        self.passiveLastEventTimestamp = passiveLastEventTimestamp
        self.journeyLastEventCoord = journeyLastEventCoord
        self.passiveLastEventCoord = passiveLastEventCoord
        self.journeyTailEvents = journeyTailEvents
        self.passiveTailEvents = passiveTailEvents
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        zoom = try container.decode(Int.self, forKey: .zoom)
        journeyRevision = try container.decodeIfPresent(Int.self, forKey: .journeyRevision) ?? 0
        passiveRevision = try container.decodeIfPresent(Int.self, forKey: .passiveRevision) ?? 0
        journeyEventCount = try container.decodeIfPresent(Int.self, forKey: .journeyEventCount) ?? 0
        passiveEventCount = try container.decodeIfPresent(Int.self, forKey: .passiveEventCount) ?? 0
        journeyLastEventTimestamp = try container.decodeIfPresent(Date.self, forKey: .journeyLastEventTimestamp)
        passiveLastEventTimestamp = try container.decodeIfPresent(Date.self, forKey: .passiveLastEventTimestamp)
        journeyLastEventCoord = try container.decodeIfPresent(CoordinateCodable.self, forKey: .journeyLastEventCoord)
        passiveLastEventCoord = try container.decodeIfPresent(CoordinateCodable.self, forKey: .passiveLastEventCoord)
        journeyTailEvents = try container.decodeIfPresent([TrackRenderEvent].self, forKey: .journeyTailEvents)
        passiveTailEvents = try container.decodeIfPresent([TrackRenderEvent].self, forKey: .passiveTailEvents)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

struct TrackTileViewport: Equatable, Sendable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double
}
