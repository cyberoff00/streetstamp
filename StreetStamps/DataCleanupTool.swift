import Foundation

struct JourneyOwnershipInfo {
    let journeyID: String
    let title: String
    let cityName: String
    let memoryCount: Int
    let distance: Double
    let endTime: Date?
    let isLikelySuspicious: Bool
    let suspiciousReason: String?
}

enum DataCleanupTool {
    /// 分析用户目录中的旅程，识别可疑的数据
    static func analyzeJourneys(userID: String) -> [JourneyOwnershipInfo] {
        let paths = StoragePath(userID: userID)
        let fm = FileManager.default

        guard let indexData = try? Data(contentsOf: paths.journeysDir.appendingPathComponent("index.json")),
              let journeyIDs = try? JSONDecoder().decode([String].self, from: indexData) else {
            return []
        }

        return journeyIDs.compactMap { id in
            analyzeJourney(id: id, journeysDir: paths.journeysDir)
        }
    }

    private static func analyzeJourney(id: String, journeysDir: URL) -> JourneyOwnershipInfo? {
        let fullURL = journeysDir.appendingPathComponent("\(id).json")
        let metaURL = journeysDir.appendingPathComponent("\(id).meta.json")

        let url = FileManager.default.fileExists(atPath: fullURL.path) ? fullURL : metaURL
        guard let data = try? Data(contentsOf: url),
              let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) else {
            return nil
        }

        // 检测可疑特征
        var suspicious = false
        var reason: String? = nil

        // 1. 检查是否有异常的城市名称（可能是其他语言或其他用户的数据）
        if let cityName = route.cityName, cityName.contains("friend") || cityName.contains("preview") {
            suspicious = true
            reason = "城市名称包含 friend/preview"
        }

        // 2. 检查是否有重复的旅程（相同时间、相同地点）
        // 这个需要在外层比较，这里先标记

        return JourneyOwnershipInfo(
            journeyID: route.id,
            title: route.customTitle ?? route.cityName ?? "未知",
            cityName: route.cityName ?? "未知",
            memoryCount: route.memories.count,
            distance: route.distance,
            endTime: route.endTime,
            isLikelySuspicious: suspicious,
            suspiciousReason: reason
        )
    }

    /// 删除指定的旅程
    static func deleteJourneys(journeyIDs: [String], userID: String) throws {
        let paths = StoragePath(userID: userID)
        let fm = FileManager.default

        // 1. 删除文件
        for id in journeyIDs {
            let files = [
                paths.journeysDir.appendingPathComponent("\(id).json"),
                paths.journeysDir.appendingPathComponent("\(id).meta.json"),
                paths.journeysDir.appendingPathComponent("\(id).delta.jsonl")
            ]
            for file in files {
                try? fm.removeItem(at: file)
            }
        }

        // 2. 更新 index.json
        let indexURL = paths.journeysDir.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           var allIDs = try? JSONDecoder().decode([String].self, from: data) {
            allIDs.removeAll { journeyIDs.contains($0) }
            let newData = try JSONEncoder().encode(allIDs)
            try newData.write(to: indexURL, options: .atomic)
        }
    }
}
