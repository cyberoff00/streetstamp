import Foundation

enum PostcardInboxStore {
    private static func key(userID: String, box: String) -> String {
        "StreetStamps.PostcardInbox.v1.\(box).\(userID)"
    }

    static func loadSent(userID: String) -> [BackendPostcardMessageDTO] {
        load(key: key(userID: userID, box: "sent"))
    }

    static func loadReceived(userID: String) -> [BackendPostcardMessageDTO] {
        load(key: key(userID: userID, box: "received"))
    }

    static func saveSent(_ items: [BackendPostcardMessageDTO], userID: String) {
        save(items, key: key(userID: userID, box: "sent"))
    }

    static func saveReceived(_ items: [BackendPostcardMessageDTO], userID: String) {
        save(items, key: key(userID: userID, box: "received"))
    }

    static func clear(userID: String) {
        UserDefaults.standard.removeObject(forKey: key(userID: userID, box: "sent"))
        UserDefaults.standard.removeObject(forKey: key(userID: userID, box: "received"))
    }

    private static func load(key: String) -> [BackendPostcardMessageDTO] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BackendPostcardMessageDTO].self, from: data)) ?? []
    }

    private static func save(_ items: [BackendPostcardMessageDTO], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
