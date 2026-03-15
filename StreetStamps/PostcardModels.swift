import Foundation

struct SendPostcardRequest: Codable {
    var clientDraftID: String
    var toUserID: String
    var cityID: String
    var cityJourneyCount: Int
    var cityName: String
    var messageText: String
    var photoURL: String
    var allowedCityIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case clientDraftID
        case toUserID
        case cityID
        case cityJourneyCount
        case cityName
        case messageText
        case photoURL
        case allowedCityIDs
    }
}

struct BackendPostcardMessageDTO: Codable, Identifiable {
    var messageID: String
    var type: String
    var fromUserID: String
    var fromDisplayName: String?
    var toUserID: String
    var toDisplayName: String?
    var cityID: String
    var cityName: String
    var photoURL: String?
    var messageText: String
    var sentAt: Date
    var clientDraftID: String
    var status: String?
    var reaction: PostcardReaction?

    var id: String { messageID }

    private enum CodingKeys: String, CodingKey {
        case messageID
        case id
        case type
        case fromUserID
        case fromDisplayName
        case toUserID
        case toDisplayName
        case cityID
        case cityName
        case photoURL
        case messageText
        case sentAt
        case clientDraftID
        case status
        case reaction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID = (try? c.decode(String.self, forKey: .messageID))
            ?? (try? c.decode(String.self, forKey: .id))
            ?? UUID().uuidString
        type = (try? c.decode(String.self, forKey: .type)) ?? "postcard"
        fromUserID = (try? c.decode(String.self, forKey: .fromUserID)) ?? ""
        fromDisplayName = try? c.decode(String.self, forKey: .fromDisplayName)
        toUserID = (try? c.decode(String.self, forKey: .toUserID)) ?? ""
        toDisplayName = try? c.decode(String.self, forKey: .toDisplayName)
        cityID = (try? c.decode(String.self, forKey: .cityID)) ?? ""
        cityName = (try? c.decode(String.self, forKey: .cityName)) ?? cityID
        photoURL = try? c.decode(String.self, forKey: .photoURL)
        messageText = (try? c.decode(String.self, forKey: .messageText)) ?? ""
        sentAt = (try? c.decode(Date.self, forKey: .sentAt)) ?? Date()
        clientDraftID = (try? c.decode(String.self, forKey: .clientDraftID)) ?? ""
        status = try? c.decode(String.self, forKey: .status)
        reaction = try? c.decode(PostcardReaction.self, forKey: .reaction)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messageID, forKey: .messageID)
        try c.encode(type, forKey: .type)
        try c.encode(fromUserID, forKey: .fromUserID)
        try c.encodeIfPresent(fromDisplayName, forKey: .fromDisplayName)
        try c.encode(toUserID, forKey: .toUserID)
        try c.encodeIfPresent(toDisplayName, forKey: .toDisplayName)
        try c.encode(cityID, forKey: .cityID)
        try c.encode(cityName, forKey: .cityName)
        try c.encodeIfPresent(photoURL, forKey: .photoURL)
        try c.encode(messageText, forKey: .messageText)
        try c.encode(sentAt, forKey: .sentAt)
        try c.encode(clientDraftID, forKey: .clientDraftID)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(reaction, forKey: .reaction)
    }
}

struct BackendPostcardsResponse: Codable {
    var items: [BackendPostcardMessageDTO]
    var cursor: String?
}

struct BackendSendPostcardResponse: Codable {
    var messageID: String
    var sentAt: Date
    var idempotent: Bool?
}

// MARK: - Postcard Reactions

struct PostcardReaction: Codable, Identifiable {
    var id: String
    var postcardMessageID: String
    var fromUserID: String
    var viewedAt: Date?
    var reactionEmoji: String?
    var comment: String?
    var reactedAt: Date?
}

struct PostcardReactionRequest: Codable {
    var reactionEmoji: String?
    var comment: String?
}

struct PostcardReactionResponse: Codable {
    var reaction: PostcardReaction
}
