import Foundation

enum LifelogMigrationService {
    static func migrateLegacyLifelogIfNeeded(paths: StoragePath) throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: paths.migrationMarkerV5_lifelogPassiveSplit.path) {
            if !fm.fileExists(atPath: paths.lifelogPassiveRouteURL.path) {
                try writeDefaultPassiveFile(to: paths.lifelogPassiveRouteURL)
            }
            return
        }

        try paths.ensureBaseDirectoriesExist()

        let legacyURL = paths.lifelogLegacyRouteURL
        let bakURL = paths.cachesDir.appendingPathComponent("lifelog_route.json.bak", isDirectory: false)

        if fm.fileExists(atPath: legacyURL.path) {
            if fm.fileExists(atPath: bakURL.path) {
                try? fm.removeItem(at: bakURL)
            }
            try fm.moveItem(at: legacyURL, to: bakURL)
        }

        if !fm.fileExists(atPath: paths.lifelogPassiveRouteURL.path) {
            try writeDefaultPassiveFile(to: paths.lifelogPassiveRouteURL)
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
}
