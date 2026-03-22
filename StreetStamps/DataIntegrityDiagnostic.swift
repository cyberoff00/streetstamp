import Foundation

struct UserDirectoryInfo {
    let userID: String
    let journeyCount: Int
    let lastModified: Date?
    let isCurrentUser: Bool
    let isFriendPreview: Bool
    let isGuestScope: Bool
    let isLocalScope: Bool
}

enum DataIntegrityDiagnostic {
    static func scanAllUserDirectories(currentUserID: String) -> [UserDirectoryInfo] {
        let fm = FileManager.default
        let paths = StoragePath(userID: currentUserID)
        let usersRoot = paths.userRoot.deletingLastPathComponent()

        guard let entries = try? fm.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { dir in
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let userID = dir.lastPathComponent
            let journeysDir = dir.appendingPathComponent("Journeys", isDirectory: true)
            let journeyCount = countJourneys(in: journeysDir)
            let lastModified = try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            return UserDirectoryInfo(
                userID: userID,
                journeyCount: journeyCount,
                lastModified: lastModified,
                isCurrentUser: userID == currentUserID,
                isFriendPreview: userID.hasPrefix("friend_preview_"),
                isGuestScope: userID.hasPrefix("guest_"),
                isLocalScope: userID.hasPrefix("local_")
            )
        }
        .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }

    private static func countJourneys(in journeysDir: URL) -> Int {
        let fm = FileManager.default
        let indexURL = journeysDir.appendingPathComponent("index.json")

        if let data = try? Data(contentsOf: indexURL),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids.count
        }

        guard let files = try? fm.contentsOfDirectory(
            at: journeysDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let journeyFiles = files.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".json") && !name.hasSuffix(".meta.json") && name != "index.json"
        }
        return journeyFiles.count
    }

    static func clearAutoRecoveryHistory() {
        UserDefaults.standard.removeObject(forKey: "streetstamps.auto_recovered_guest_sources.v1")
        print("✅ 已清除自动恢复历史记录")
    }

    static func removeFriendPreviewDirectories() throws {
        let fm = FileManager.default
        let tempUserID = "local_temp"
        let paths = StoragePath(userID: tempUserID)
        let usersRoot = paths.userRoot.deletingLastPathComponent()

        guard let entries = try? fm.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var removed = 0
        for dir in entries {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let userID = dir.lastPathComponent
            if userID.hasPrefix("friend_preview_") {
                try? fm.removeItem(at: dir)
                removed += 1
            }
        }
        print("✅ 已删除 \(removed) 个朋友预览目录")
    }
}
