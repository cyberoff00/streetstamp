import Foundation

enum LifelogMigrationService {
    static func migrateLegacyLifelogIfNeeded(paths: StoragePath) throws {
        let fm = FileManager.default
        let passiveURL = paths.lifelogPassiveRouteURL
        let legacyURL = paths.lifelogLegacyRouteURL
        let bakURL = paths.cachesDir.appendingPathComponent("lifelog_route.json.bak", isDirectory: false)

        try paths.ensureBaseDirectoriesExist()

        if fm.fileExists(atPath: paths.migrationMarkerV5_lifelogPassiveSplit.path) {
            try recoverPassiveFromBackupIfNeeded(passiveURL: passiveURL, backupURL: bakURL, fileManager: fm)
            if !fm.fileExists(atPath: passiveURL.path) {
                try writeDefaultPassiveFile(to: passiveURL)
            }
            return
        }

        if fm.fileExists(atPath: legacyURL.path) {
            if fm.fileExists(atPath: bakURL.path) {
                try? fm.removeItem(at: bakURL)
            }
            try fm.copyItem(at: legacyURL, to: bakURL)

            let legacyHasTrack = hasTrackData(at: legacyURL)
            let passiveHasTrack = hasTrackData(at: passiveURL)
            if legacyHasTrack && !passiveHasTrack {
                if fm.fileExists(atPath: passiveURL.path) {
                    try? fm.removeItem(at: passiveURL)
                }
                try fm.moveItem(at: legacyURL, to: passiveURL)
            } else {
                try? fm.removeItem(at: legacyURL)
            }
        }

        try recoverPassiveFromBackupIfNeeded(passiveURL: passiveURL, backupURL: bakURL, fileManager: fm)
        if !fm.fileExists(atPath: passiveURL.path) {
            try writeDefaultPassiveFile(to: passiveURL)
        }

        fm.createFile(atPath: paths.migrationMarkerV5_lifelogPassiveSplit.path, contents: Data())
    }

    static func migrateLegacyLifelogIfNeededAsync(paths: StoragePath) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                try? migrateLegacyLifelogIfNeeded(paths: paths)
                continuation.resume()
            }
        }
    }

    private static func writeDefaultPassiveFile(to url: URL) throws {
        let payload = Data("{}".utf8)
        try payload.write(to: url, options: .atomic)
    }

    private static func recoverPassiveFromBackupIfNeeded(
        passiveURL: URL,
        backupURL: URL,
        fileManager fm: FileManager
    ) throws {
        guard fm.fileExists(atPath: backupURL.path) else { return }
        guard hasTrackData(at: backupURL) else { return }

        if fm.fileExists(atPath: passiveURL.path) {
            guard !hasTrackData(at: passiveURL) else { return }
            try? fm.removeItem(at: passiveURL)
        }
        try fm.copyItem(at: backupURL, to: passiveURL)
    }

    private static func hasTrackData(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return false }

        if let dict = obj as? [String: Any] {
            let points = dict["points"] as? [Any] ?? []
            let coordinates = dict["coordinates"] as? [Any] ?? []
            return !points.isEmpty || !coordinates.isEmpty
        }
        if let array = obj as? [Any] {
            return !array.isEmpty
        }
        return false
    }
}
