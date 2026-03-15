import Foundation

enum CurrentUserRepairDiagnostic {
    static func buildReport(
        activeLocalProfileID: String,
        currentGuestScopedUserID: String,
        currentAccountUserID: String?
    ) throws -> CurrentUserRepairReport {
        let paths = StoragePath(userID: activeLocalProfileID)
        let policy = CurrentUserRepairPolicy(
            activeLocalProfileID: activeLocalProfileID,
            currentGuestScopedUserID: currentGuestScopedUserID,
            currentAccountUserID: currentAccountUserID
        )

        let indexedIDs = loadIndexedJourneyIDs(from: paths.journeysDir)
        let actualIDs = loadActualJourneyIDs(from: paths.journeysDir)
        let sourceMap = loadSourceMap(from: paths.journeyRepairSourcesURL)

        let allowed = actualIDs.filter { disposition(for: $0, policy: policy, sourceMap: sourceMap) != .quarantine }
        let quarantined = actualIDs.filter { disposition(for: $0, policy: policy, sourceMap: sourceMap) == .quarantine }
        let missingFromIndex = actualIDs.filter { !indexedIDs.contains($0) }
        let orphanedIndexed = indexedIDs.filter { !actualIDs.contains($0) }

        return CurrentUserRepairReport(
            allowedJourneyIDs: allowed,
            quarantinedJourneyIDs: quarantined,
            missingFromIndexJourneyIDs: missingFromIndex,
            orphanedIndexedJourneyIDs: orphanedIndexed
        )
    }

    static func loadIndexedJourneyIDs(from journeysDir: URL) -> [String] {
        let indexURL = journeysDir.appendingPathComponent("index.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: indexURL),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return orderedUnique(ids)
    }

    static func loadActualJourneyIDs(from journeysDir: URL) -> [String] {
        let fm = FileManager.default
        guard
            fm.fileExists(atPath: journeysDir.path),
            let files = try? fm.contentsOfDirectory(at: journeysDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            return []
        }

        let ids = files.compactMap { url -> String? in
            let name = url.lastPathComponent
            guard name != "index.json" else { return nil }
            if name.hasSuffix(".meta.json") {
                return String(name.dropLast(".meta.json".count))
            }
            if name.hasSuffix(".delta.jsonl") {
                return String(name.dropLast(".delta.jsonl".count))
            }
            guard name.hasSuffix(".json") else { return nil }
            return String(name.dropLast(".json".count))
        }
        return orderedUnique(ids)
    }

    static func loadSourceMap(from url: URL) -> [String: JourneyRepairSource] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: JourneyRepairSource].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func disposition(
        for journeyID: String,
        policy: CurrentUserRepairPolicy,
        sourceMap: [String: JourneyRepairSource]
    ) -> JourneyRepairDisposition {
        guard let source = sourceMap[journeyID] else {
            // Old local data often has no source metadata yet. Keep it visible and let
            // the manual repair entry focus on index/city-cache self-healing unless we
            // have explicit evidence that a journey came from an invalid source.
            return .allow
        }
        return policy.disposition(for: source)
    }

    private static func orderedUnique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in ids where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
}
