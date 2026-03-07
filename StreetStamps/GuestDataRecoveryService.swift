import Foundation

struct GuestRecoveryCandidate: Identifiable, Hashable {
    let userID: String
    let journeyCount: Int
    let memoryCount: Int
    let photoCount: Int
    let lifelogPointCount: Int
    let topCities: [String]
    let lastModified: Date?

    var id: String { userID }
}

struct GuestRecoveryResult {
    let mergedJourneyCount: Int
    let copiedJourneyFiles: Int
    let copiedPhotos: Int
    let copiedThumbnails: Int
    let replacedLifelog: Bool
    let mergedMood: Bool
}

struct GuestRecoveryOptions {
    let replaceExistingJourneys: Bool
    let replaceLifelogWhenSourceIsMoreComplete: Bool

    static let conservativeAuto = GuestRecoveryOptions(
        replaceExistingJourneys: false,
        replaceLifelogWhenSourceIsMoreComplete: false
    )

    static let manualImport = GuestRecoveryOptions(
        replaceExistingJourneys: true,
        replaceLifelogWhenSourceIsMoreComplete: true
    )
}

enum GuestDataRecoveryError: LocalizedError {
    case sourceNotFound
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "未找到要恢复的游客数据目录"
        case .invalidSource:
            return "恢复源无效"
        }
    }
}

enum GuestDataRecoveryService {
    static func discoverCandidates(currentUserID: String) -> [GuestRecoveryCandidate] {
        let fm = FileManager.default
        let currentPaths = StoragePath(userID: currentUserID)
        let usersRoot = currentPaths.userRoot.deletingLastPathComponent()
        guard fm.fileExists(atPath: usersRoot.path) else { return [] }

        let entries = (try? fm.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [GuestRecoveryCandidate] = []
        for dir in entries {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let userID = dir.lastPathComponent
            guard userID.hasPrefix("guest_"), userID != currentUserID else { continue }

            let summary = summarize(userID: userID)
            let hasUsefulData =
                summary.journeyCount > 0 ||
                summary.memoryCount > 0 ||
                summary.photoCount > 0 ||
                summary.lifelogPointCount > 0
            guard hasUsefulData else { continue }

            out.append(summary)
        }

        return out.sorted {
            ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast)
        }
    }

    static func recover(
        from sourceUserID: String,
        to targetUserID: String,
        options: GuestRecoveryOptions = .conservativeAuto
    ) throws -> GuestRecoveryResult {
        guard sourceUserID != targetUserID else {
            throw GuestDataRecoveryError.invalidSource
        }

        let fm = FileManager.default
        let source = StoragePath(userID: sourceUserID)
        let target = StoragePath(userID: targetUserID)

        guard fm.fileExists(atPath: source.userRoot.path) else {
            throw GuestDataRecoveryError.sourceNotFound
        }

        try target.ensureBaseDirectoriesExist()

        let targetBeforeIDs = loadJourneyIDs(from: target.journeysDir)
        let copiedJourneyFiles = try copyJourneyFiles(
            sourceDir: source.journeysDir,
            targetDir: target.journeysDir,
            replaceExisting: options.replaceExistingJourneys
        )
        let targetAfterIDs = try mergeJourneyIndex(sourceDir: source.journeysDir, targetDir: target.journeysDir)

        let copiedPhotos = try copyMissingFiles(from: source.photosDir, to: target.photosDir)
        let copiedThumbnails = try copyMissingFiles(from: source.thumbnailsDir, to: target.thumbnailsDir)
        let replacedLifelog = try mergeLifelog(
            sourceURL: source.lifelogRouteURL,
            targetURL: target.lifelogRouteURL,
            allowReplacement: options.replaceLifelogWhenSourceIsMoreComplete
        )
        let mergedMood = try mergeMood(
            sourceURL: source.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false),
            targetURL: target.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        )

        let mergedJourneyCount = max(0, targetAfterIDs.count - targetBeforeIDs.count)

        return GuestRecoveryResult(
            mergedJourneyCount: mergedJourneyCount,
            copiedJourneyFiles: copiedJourneyFiles,
            copiedPhotos: copiedPhotos,
            copiedThumbnails: copiedThumbnails,
            replacedLifelog: replacedLifelog,
            mergedMood: mergedMood
        )
    }

    private static func summarize(userID: String) -> GuestRecoveryCandidate {
        let fm = FileManager.default
        let paths = StoragePath(userID: userID)
        let journeyIDs = loadJourneyIDs(from: paths.journeysDir)

        var memoryCount = 0
        var cityFreq: [String: Int] = [:]
        for id in journeyIDs {
            guard let route = loadJourneyRoute(id: id, journeysDir: paths.journeysDir) else { continue }
            memoryCount += route.memories.count
            let city = bestCityName(route)
            if !city.isEmpty {
                cityFreq[city, default: 0] += 1
            }
        }

        let topCities = cityFreq
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map(\.key)

        let photoCount: Int = {
            guard fm.fileExists(atPath: paths.photosDir.path) else { return 0 }
            let files = (try? fm.contentsOfDirectory(at: paths.photosDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return files.count
        }()

        let lifelogPointCount = lifelogCount(url: paths.lifelogRouteURL)
        let lastModified = (try? paths.userRoot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil

        return GuestRecoveryCandidate(
            userID: userID,
            journeyCount: journeyIDs.count,
            memoryCount: memoryCount,
            photoCount: photoCount,
            lifelogPointCount: lifelogPointCount,
            topCities: topCities,
            lastModified: lastModified
        )
    }

    private static func bestCityName(_ route: JourneyRoute) -> String {
        let candidates = [
            route.cityName,
            route.currentCity,
            route.canonicalCity,
            route.customTitle
        ]
        for raw in candidates {
            let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, value.lowercased() != "unknown", value != L10n.t("unknown") {
                return value
            }
        }
        return L10n.t("unknown")
    }

    private static func loadJourneyRoute(id: String, journeysDir: URL) -> JourneyRoute? {
        let fm = FileManager.default
        let full = journeysDir.appendingPathComponent("\(id).json")
        let meta = journeysDir.appendingPathComponent("\(id).meta.json")

        let candidateURL: URL? = {
            if fm.fileExists(atPath: full.path) { return full }
            if fm.fileExists(atPath: meta.path) { return meta }
            return nil
        }()

        guard let url = candidateURL,
              let data = try? Data(contentsOf: url),
              let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) else {
            return nil
        }
        return route
    }

    private static func loadJourneyIDs(from journeysDir: URL) -> [String] {
        let fm = FileManager.default
        let indexURL = journeysDir.appendingPathComponent("index.json")
        if fm.fileExists(atPath: indexURL.path),
           let data = try? Data(contentsOf: indexURL),
           let ids = try? JSONDecoder().decode([String].self, from: data),
           !ids.isEmpty {
            return orderedUnique(ids)
        }

        guard fm.fileExists(atPath: journeysDir.path),
              let files = try? fm.contentsOfDirectory(at: journeysDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        let inferred = files.compactMap { url -> String? in
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
        return orderedUnique(inferred)
    }

    private static func mergeJourneyIndex(sourceDir: URL, targetDir: URL) throws -> [String] {
        let sourceIDs = loadJourneyIDs(from: sourceDir)
        let targetIDs = loadJourneyIDs(from: targetDir)
        let mergedIDs = orderedUnique(targetIDs + sourceIDs)

        let indexURL = targetDir.appendingPathComponent("index.json")
        let data = try JSONEncoder().encode(mergedIDs)
        try data.write(to: indexURL, options: .atomic)
        return mergedIDs
    }

    private static func copyJourneyFiles(
        sourceDir: URL,
        targetDir: URL,
        replaceExisting: Bool
    ) throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDir.path) else { return 0 }
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var copied = 0
        let sourceIDs = loadJourneyIDs(from: sourceDir)

        for id in sourceIDs {
            let sourceFiles = journeyFileURLs(for: id, in: sourceDir, fileManager: fm)
            guard !sourceFiles.isEmpty else { continue }

            let targetFiles = journeyFileURLs(for: id, in: targetDir, fileManager: fm)
            if targetFiles.isEmpty {
                copied += try replaceJourneyFiles(for: id, sourceDir: sourceDir, targetDir: targetDir, fileManager: fm)
                continue
            }

            guard replaceExisting else { continue }

            guard shouldPreferSourceJourney(id: id, sourceDir: sourceDir, targetDir: targetDir, sourceFiles: sourceFiles, targetFiles: targetFiles) else {
                continue
            }

            copied += try replaceJourneyFiles(for: id, sourceDir: sourceDir, targetDir: targetDir, fileManager: fm)
        }

        return copied
    }

    private static func journeyFileURLs(for id: String, in dir: URL, fileManager fm: FileManager) -> [URL] {
        let names = [
            "\(id).json",
            "\(id).meta.json",
            "\(id).delta.jsonl"
        ]
        return names.compactMap { name in
            let url = dir.appendingPathComponent(name, isDirectory: false)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
    }

    private static func replaceJourneyFiles(for id: String, sourceDir: URL, targetDir: URL, fileManager fm: FileManager) throws -> Int {
        let sourceFiles = journeyFileURLs(for: id, in: sourceDir, fileManager: fm)
        guard !sourceFiles.isEmpty else { return 0 }

        for targetFile in journeyFileURLs(for: id, in: targetDir, fileManager: fm) {
            try fm.removeItem(at: targetFile)
        }

        var copied = 0
        for sourceFile in sourceFiles {
            let destination = targetDir.appendingPathComponent(sourceFile.lastPathComponent, isDirectory: false)
            try fm.copyItem(at: sourceFile, to: destination)
            copied += 1
        }
        return copied
    }

    private static func shouldPreferSourceJourney(
        id: String,
        sourceDir: URL,
        targetDir: URL,
        sourceFiles: [URL],
        targetFiles: [URL]
    ) -> Bool {
        let sourceRoute = loadJourneyRoute(id: id, journeysDir: sourceDir)
        let targetRoute = loadJourneyRoute(id: id, journeysDir: targetDir)

        if let sourceRoute, let targetRoute {
            let sourceFreshness = journeyFreshnessDate(sourceRoute)
            let targetFreshness = journeyFreshnessDate(targetRoute)
            if let sourceFreshness, let targetFreshness, sourceFreshness != targetFreshness {
                return sourceFreshness > targetFreshness
            }
            if let richerSource = richerJourneyWins(sourceRoute, targetRoute) {
                return richerSource
            }
        } else if sourceRoute != nil, targetRoute == nil {
            return true
        } else if sourceRoute == nil, targetRoute != nil {
            return false
        }

        let sourceModified = latestModificationDate(of: sourceFiles)
        let targetModified = latestModificationDate(of: targetFiles)
        return sourceModified > targetModified
    }

    private static func journeyFreshnessDate(_ route: JourneyRoute) -> Date? {
        let latestMemory = route.memories.map(\.timestamp).max()
        return [route.endTime, route.startTime, latestMemory].compactMap { $0 }.max()
    }

    private static func richerJourneyWins(_ source: JourneyRoute, _ target: JourneyRoute) -> Bool? {
        if source.coordinates.count != target.coordinates.count {
            return source.coordinates.count > target.coordinates.count
        }
        if source.memories.count != target.memories.count {
            return source.memories.count > target.memories.count
        }

        let sourceLatestMemory = source.memories.map(\.timestamp).max() ?? .distantPast
        let targetLatestMemory = target.memories.map(\.timestamp).max() ?? .distantPast
        if sourceLatestMemory != targetLatestMemory {
            return sourceLatestMemory > targetLatestMemory
        }

        if abs(source.distance - target.distance) > 0.000_1 {
            return source.distance > target.distance
        }
        return nil
    }

    private static func latestModificationDate(of urls: [URL]) -> Date {
        let fm = FileManager.default
        var latest: Date = .distantPast
        for url in urls {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let modified = attrs[.modificationDate] as? Date else {
                continue
            }
            if modified > latest {
                latest = modified
            }
        }
        return latest
    }

    private static func copyMissingFiles(from sourceDir: URL, to targetDir: URL) throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDir.path) else { return 0 }
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let sourceFiles = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var copied = 0

        for src in sourceFiles {
            guard (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let dst = targetDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) { continue }
            try fm.copyItem(at: src, to: dst)
            copied += 1
        }
        return copied
    }

    private static func mergeLifelog(
        sourceURL: URL,
        targetURL: URL,
        allowReplacement: Bool
    ) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return false }

        let sourceCount = lifelogCount(url: sourceURL)
        let targetCount = lifelogCount(url: targetURL)
        if targetCount > 0 && !allowReplacement {
            return false
        }
        guard sourceCount > targetCount || targetCount == 0 else { return false }

        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: targetURL.path) {
            try fm.removeItem(at: targetURL)
        }
        try fm.copyItem(at: sourceURL, to: targetURL)
        return true
    }

    private static func mergeMood(sourceURL: URL, targetURL: URL) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return false }

        let source = loadMood(url: sourceURL)
        guard !source.isEmpty else { return false }

        var merged = source
        let existing = loadMood(url: targetURL)
        for (key, value) in existing {
            merged[key] = value
        }

        guard merged != existing else { return false }

        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(merged)
        try data.write(to: targetURL, options: .atomic)
        return true
    }

    private static func loadMood(url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func lifelogCount(url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LifelogProbe.self, from: data) else {
            return 0
        }
        if let points = payload.points {
            return points.count
        }
        return payload.coordinates?.count ?? 0
    }

    private static func orderedUnique(_ ids: [String]) -> [String] {
        var set = Set<String>()
        var out: [String] = []
        out.reserveCapacity(ids.count)
        for id in ids {
            if id.isEmpty { continue }
            if set.insert(id).inserted {
                out.append(id)
            }
        }
        return out
    }
}

private struct LifelogProbe: Codable {
    struct Point: Codable {
        let lat: Double
        let lon: Double
        let timestamp: Date
    }

    let points: [Point]?
    let coordinates: [CoordinateCodable]?
}
