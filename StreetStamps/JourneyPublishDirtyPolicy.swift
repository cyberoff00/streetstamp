import Foundation

enum JourneyEditSaveAction {
    case saveLocal
    case promptRepublish
}

enum JourneyPublishDirtyPolicy {

    static func evaluateSaveAction(
        visibility: JourneyVisibility,
        snapshotMemories: [JourneyMemory],
        draftMemories: [JourneyMemory],
        snapshotTitle: String,
        draftTitle: String,
        snapshotOverallMemory: String,
        draftOverallMemory: String,
        snapshotOverallMemoryImagePaths: [String],
        draftOverallMemoryImagePaths: [String],
        snapshotOverallMemoryRemoteImageURLs: [String] = [],
        draftOverallMemoryRemoteImageURLs: [String] = []
    ) -> JourneyEditSaveAction {
        guard visibility == .public || visibility == .friendsOnly else {
            return .saveLocal
        }
        guard hasContentChanged(
            snapshotMemories: snapshotMemories,
            draftMemories: draftMemories,
            snapshotTitle: snapshotTitle,
            draftTitle: draftTitle,
            snapshotOverallMemory: snapshotOverallMemory,
            draftOverallMemory: draftOverallMemory,
            snapshotOverallMemoryImagePaths: snapshotOverallMemoryImagePaths,
            draftOverallMemoryImagePaths: draftOverallMemoryImagePaths,
            snapshotOverallMemoryRemoteImageURLs: snapshotOverallMemoryRemoteImageURLs,
            draftOverallMemoryRemoteImageURLs: draftOverallMemoryRemoteImageURLs
        ) else {
            return .saveLocal
        }
        return .promptRepublish
    }

    static func hasContentChanged(
        snapshotMemories: [JourneyMemory],
        draftMemories: [JourneyMemory],
        snapshotTitle: String,
        draftTitle: String,
        snapshotOverallMemory: String,
        draftOverallMemory: String,
        snapshotOverallMemoryImagePaths: [String],
        draftOverallMemoryImagePaths: [String],
        snapshotOverallMemoryRemoteImageURLs: [String] = [],
        draftOverallMemoryRemoteImageURLs: [String] = []
    ) -> Bool {
        let normalizedSnapshotTitle = snapshotTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDraftTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSnapshotTitle != normalizedDraftTitle { return true }

        let normalizedSnapshotOverall = snapshotOverallMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDraftOverall = draftOverallMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSnapshotOverall != normalizedDraftOverall { return true }

        if snapshotOverallMemoryImagePaths != draftOverallMemoryImagePaths { return true }
        if snapshotOverallMemoryRemoteImageURLs != draftOverallMemoryRemoteImageURLs { return true }

        if snapshotMemories != draftMemories { return true }

        return false
    }
}
