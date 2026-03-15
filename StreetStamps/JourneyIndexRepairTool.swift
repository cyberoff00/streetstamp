import Foundation

enum JourneyIndexRepairTool {
    /// 强制重建 index.json，扫描所有实际存在的旅程文件
    static func forceRebuildIndex(userID: String) throws {
        try rebuildIndex(userID: userID, allowedJourneyIDs: nil)
    }

    static func rebuildIndex(userID: String, allowedJourneyIDs: [String]?) throws {
        let paths = StoragePath(userID: userID)
        let fm = FileManager.default
        let journeysDir = paths.journeysDir
        let indexURL = journeysDir.appendingPathComponent("index.json")

        guard fm.fileExists(atPath: journeysDir.path) else {
            throw NSError(domain: "JourneyIndexRepair", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Journeys 目录不存在"])
        }

        let entries = try fm.contentsOfDirectory(at: journeysDir,
                                                 includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])
        let allowedSet = allowedJourneyIDs.map(Set.init)
        var summaries: [JourneySummary] = []

        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let name = url.lastPathComponent
            if name == "index.json" { continue }

            let id: String?
            if name.hasSuffix(".meta.json") {
                id = String(name.dropLast(".meta.json".count))
            } else if name.hasSuffix(".json"), !name.hasSuffix(".delta.json") {
                id = String(name.dropLast(".json".count))
            } else if name.hasSuffix(".delta.jsonl") {
                id = String(name.dropLast(".delta.jsonl".count))
            } else {
                id = nil
            }

            guard let id, !id.isEmpty else { continue }
            if let allowedSet, !allowedSet.contains(id) { continue }
            guard summaries.contains(where: { $0.id == id }) == false else { continue }
            summaries.append(buildSummary(for: id, journeysDir: journeysDir))
        }

        let ordered = summaries.sorted(by: compareSummaries).map(\.id)
        let data = try JSONEncoder().encode(ordered)
        try data.write(to: indexURL, options: .atomic)

        print("✅ 重建 index.json: 发现 \(ordered.count) 个旅程")
    }

    private static func buildSummary(for id: String, journeysDir: URL) -> JourneySummary {
        let fullURL = journeysDir.appendingPathComponent("\(id).json", isDirectory: false)
        let metaURL = journeysDir.appendingPathComponent("\(id).meta.json", isDirectory: false)

        let route: JourneyRoute? = {
            if let data = try? Data(contentsOf: fullURL),
               let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) {
                return route
            }
            if let data = try? Data(contentsOf: metaURL),
               let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) {
                return route
            }
            return nil
        }()

        let modificationDate =
            (try? fullURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
            (try? metaURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        return JourneySummary(
            id: id,
            startTime: route?.startTime,
            endTime: route?.endTime,
            modificationDate: modificationDate
        )
    }

    private static func compareSummaries(lhs: JourneySummary, rhs: JourneySummary) -> Bool {
        let lhsOngoing = lhs.endTime == nil
        let rhsOngoing = rhs.endTime == nil
        if lhsOngoing != rhsOngoing {
            return lhsOngoing
        }

        let lhsPrimary = lhs.endTime ?? lhs.startTime ?? lhs.modificationDate ?? .distantPast
        let rhsPrimary = rhs.endTime ?? rhs.startTime ?? rhs.modificationDate ?? .distantPast
        if lhsPrimary != rhsPrimary {
            return lhsPrimary > rhsPrimary
        }

        return lhs.id < rhs.id
    }

    private struct JourneySummary {
        let id: String
        let startTime: Date?
        let endTime: Date?
        let modificationDate: Date?
    }
}
