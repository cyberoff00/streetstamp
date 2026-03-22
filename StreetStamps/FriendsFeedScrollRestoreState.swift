import Foundation

struct FriendsFeedScrollRestoreState {
    private(set) var lastOpenedEventID: String?
    private(set) var pendingRestoreEventID: String?

    mutating func recordOpen(eventID: String) {
        let trimmed = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastOpenedEventID = trimmed
    }

    mutating func prepareRestoreOnReturn() {
        pendingRestoreEventID = lastOpenedEventID
    }

    mutating func consumeRestoreRequest() {
        pendingRestoreEventID = nil
    }
}
