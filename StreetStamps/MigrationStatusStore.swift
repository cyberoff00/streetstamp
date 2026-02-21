import Foundation

struct MigrationStatusStore {
    private static let key = "streetstamps.migration.last_report"

    static func save(_ message: String) {
        UserDefaults.standard.set(message, forKey: key)
    }

    static func lastMessage() -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
