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
    var photoURL: String
    var messageText: String
    var sentAt: Date
    var clientDraftID: String
    var status: String?

    var id: String { messageID }

    private enum CodingKeys: String, CodingKey {
        case messageID
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
