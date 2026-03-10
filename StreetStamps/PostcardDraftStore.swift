import Foundation

enum PostcardDraftStatus: String, Codable {
    case draft
    case sending
    case sent
    case failed
}

struct PostcardDraft: Codable, Identifiable, Equatable {
    var draftID: String
    var clientDraftID: String
    var toUserID: String
    var toDisplayName: String?
    var cityID: String
    var cityName: String
    var photoLocalPath: String
    var message: String
    var status: PostcardDraftStatus
    var retryCount: Int
    var lastError: String?
    var messageID: String?
    var sentAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var id: String { draftID }
}

enum PostcardDraftStore {
    private static func key(userID: String) -> String {
        "StreetStamps.PostcardDrafts.v1.\(userID)"
    }

    static func load(userID: String) -> [PostcardDraft] {
        let k = key(userID: userID)
        guard let data = UserDefaults.standard.data(forKey: k) else { return [] }
        return (try? JSONDecoder().decode([PostcardDraft].self, from: data)) ?? []
    }

    static func save(_ drafts: [PostcardDraft], userID: String) {
        let k = key(userID: userID)
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }

    static func clear(userID: String) {
        UserDefaults.standard.removeObject(forKey: key(userID: userID))
    }
}
