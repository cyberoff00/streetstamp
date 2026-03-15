import Foundation

enum JourneyRepairSourceStore {
    static func load(userID: String) -> [String: JourneyRepairSource] {
        let paths = StoragePath(userID: userID)
        guard
            let data = try? Data(contentsOf: paths.journeyRepairSourcesURL),
            let decoded = try? JSONDecoder().decode([String: JourneyRepairSource].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    static func merge(_ entries: [String: JourneyRepairSource], userID: String) {
        guard !entries.isEmpty else { return }
        let paths = StoragePath(userID: userID)
        var current = load(userID: userID)
        for (id, source) in entries {
            current[id] = source
        }
        if let data = try? JSONEncoder().encode(current) {
            try? paths.ensureBaseDirectoriesExist()
            try? data.write(to: paths.journeyRepairSourcesURL, options: .atomic)
        }
    }
}
