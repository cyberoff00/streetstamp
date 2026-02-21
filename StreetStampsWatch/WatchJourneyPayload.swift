import Foundation

enum WatchJourneyEvent: String, Codable {
    case started
    case resumed
    case paused
    case progress
    case ended
}

struct WatchJourneyPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var speed: Double
    var altitude: Double

    var isValidCoordinate: Bool {
        abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

struct WatchJourneyEnvelope: Codable {
    static let payloadKey = "streetstamps.watch.journey.payload"

    var schemaVersion: Int
    var eventID: String
    var journeyID: String
    var event: WatchJourneyEvent
    var startedAt: Date?
    var endedAt: Date?
    var trackingModeRaw: String
    var points: [WatchJourneyPoint]
    var totalPointCount: Int?
    var chunkIndex: Int?
    var chunkCount: Int?
    var sentAt: Date

    init(
        schemaVersion: Int = 1,
        eventID: String = UUID().uuidString,
        journeyID: String,
        event: WatchJourneyEvent,
        startedAt: Date?,
        endedAt: Date? = nil,
        trackingModeRaw: String = "sport",
        points: [WatchJourneyPoint],
        totalPointCount: Int? = nil,
        chunkIndex: Int? = nil,
        chunkCount: Int? = nil,
        sentAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.journeyID = journeyID
        self.event = event
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trackingModeRaw = trackingModeRaw
        self.points = points
        self.totalPointCount = totalPointCount
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.sentAt = sentAt
    }

    func asUserInfo() -> [String: Any]? {
        guard let data = try? Self.encoder.encode(self) else { return nil }
        return [Self.payloadKey: data]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
