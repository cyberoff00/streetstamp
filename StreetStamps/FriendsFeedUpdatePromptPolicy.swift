import Foundation

enum FriendsFeedUpdatePromptPolicy {
    static func hasUnseenEvents(currentEventIDs: [String], candidateEventIDs: [String]) -> Bool {
        let current = Set(currentEventIDs)
        return candidateEventIDs.contains { !current.contains($0) }
    }
}
