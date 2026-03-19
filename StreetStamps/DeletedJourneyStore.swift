import Foundation
enum DeletedJourneyStore {
    static func load(userID: String) -> Set<String> {
        let paths = StoragePath(userID: userID)
        guard
            let data = try? Data(contentsOf: paths.deletedJourneyIDsURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(decoded.filter { !$0.isEmpty })
    }

    static func record(_ ids: [String], userID: String) {
        let incoming = Set(ids.filter { !$0.isEmpty })
        guard !incoming.isEmpty else { return }

        let paths = StoragePath(userID: userID)
        var current = load(userID: userID)
        current.formUnion(incoming)

        guard let data = try? JSONEncoder().encode(Array(current).sorted()) else { return }
        try? paths.ensureBaseDirectoriesExist()
        try? data.write(to: paths.deletedJourneyIDsURL, options: .atomic)
    }
}
