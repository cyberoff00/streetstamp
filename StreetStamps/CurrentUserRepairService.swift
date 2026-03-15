import Foundation

enum CurrentUserRepairService {
    static func repairCurrentUser(
        activeLocalProfileID: String,
        report: CurrentUserRepairReport
    ) throws -> CurrentUserRepairResult {
        let paths = StoragePath(userID: activeLocalProfileID)
        try paths.ensureBaseDirectoriesExist()

        for id in report.quarantinedJourneyIDs {
            try moveJourneyFilesToQuarantine(id: id, paths: paths)
        }

        try JourneyIndexRepairTool.rebuildIndex(
            userID: activeLocalProfileID,
            allowedJourneyIDs: report.allowedJourneyIDs
        )

        return CurrentUserRepairResult(
            keptJourneyIDs: report.allowedJourneyIDs,
            quarantinedJourneyIDs: report.quarantinedJourneyIDs
        )
    }

    private static func moveJourneyFilesToQuarantine(id: String, paths: StoragePath) throws {
        let fm = FileManager.default
        try paths.ensureDirectory(paths.quarantineDir)

        let fileNames = [
            "\(id).json",
            "\(id).meta.json",
            "\(id).delta.jsonl"
        ]

        for fileName in fileNames {
            let sourceURL = paths.journeysDir.appendingPathComponent(fileName, isDirectory: false)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = paths.quarantineDir.appendingPathComponent(fileName, isDirectory: false)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: sourceURL, to: destinationURL)
        }
    }
}
