import Foundation

struct SendPostcardRequest: Codable {
    var clientDraftID: String
    var toUserID: String
    var cityID: String
    var cityName: String
    var messageText: String
    var photoURL: String
    var allowedCityIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case clientDraftID
        case toUserID
        case cityID
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
    var cityID: String
    var cityName: String
    var photoURL: String?
    var messageText: String
    var sentAt: Date
    var clientDraftID: String
    var status: String?

    var id: String { messageID }

    private enum CodingKeys: String, CodingKey {
        case messageID
        case id
        case type
        case fromUserID
        case fromDisplayName
        case toUserID
        case cityID
        case cityName
        case photoURL
        case messageText
        case sentAt
        case clientDraftID
        case status
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
        cityID = (try? c.decode(String.self, forKey: .cityID)) ?? ""
        cityName = (try? c.decode(String.self, forKey: .cityName)) ?? cityID
        photoURL = try? c.decode(String.self, forKey: .photoURL)
        messageText = (try? c.decode(String.self, forKey: .messageText)) ?? ""
        sentAt = (try? c.decode(Date.self, forKey: .sentAt)) ?? Date()
        clientDraftID = (try? c.decode(String.self, forKey: .clientDraftID)) ?? ""
        status = try? c.decode(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messageID, forKey: .messageID)
        try c.encode(type, forKey: .type)
        try c.encode(fromUserID, forKey: .fromUserID)
        try c.encodeIfPresent(fromDisplayName, forKey: .fromDisplayName)
        try c.encode(toUserID, forKey: .toUserID)
        try c.encode(cityID, forKey: .cityID)
        try c.encode(cityName, forKey: .cityName)
        try c.encodeIfPresent(photoURL, forKey: .photoURL)
        try c.encode(messageText, forKey: .messageText)
        try c.encode(sentAt, forKey: .sentAt)
        try c.encode(clientDraftID, forKey: .clientDraftID)
        try c.encodeIfPresent(status, forKey: .status)
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
