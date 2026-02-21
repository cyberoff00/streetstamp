//
//  JourneyMemoryDraftStore.swift
//  StreetStamps
//
//  Draft persistence for Journey Memory Detail editor.
//  Keeps edit state when user switches tabs / navigates away, and restores after relaunch.
//

import Foundation

struct JourneyMemoryDetailDraft: Codable, Equatable {
    var memories: [JourneyMemory]
    var focusedMemoryID: String?
}

enum JourneyMemoryDetailDraftStore {
    private static func key(userID: String, journeyID: String) -> String {
        "StreetStamps.JourneyMemoryDetailDraft.v1.\(userID).\(journeyID)"
    }

    static func load(userID: String, journeyID: String) -> JourneyMemoryDetailDraft? {
        let k = key(userID: userID, journeyID: journeyID)
        guard let data = UserDefaults.standard.data(forKey: k) else { return nil }
        return try? JSONDecoder().decode(JourneyMemoryDetailDraft.self, from: data)
    }

    static func save(_ draft: JourneyMemoryDetailDraft, userID: String, journeyID: String) {
        let k = key(userID: userID, journeyID: journeyID)
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }

    static func clear(userID: String, journeyID: String) {
        let k = key(userID: userID, journeyID: journeyID)
        UserDefaults.standard.removeObject(forKey: k)
    }
}

enum JourneyMemoryDetailResumeStore {
    private static func key(userID: String, journeyID: String) -> String {
        "StreetStamps.JourneyMemoryDetailResume.v1.\(userID).\(journeyID)"
    }

    static func shouldResume(userID: String, journeyID: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(userID: userID, journeyID: journeyID))
    }

    static func set(_ v: Bool, userID: String, journeyID: String) {
        UserDefaults.standard.set(v, forKey: key(userID: userID, journeyID: journeyID))
    }
}
