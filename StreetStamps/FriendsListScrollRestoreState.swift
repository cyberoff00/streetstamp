import Foundation

struct FriendsListScrollRestoreState {
    private(set) var lastOpenedFriendID: String?
    private(set) var pendingRestoreFriendID: String?

    mutating func recordOpen(friendID: String) {
        let trimmed = friendID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastOpenedFriendID = trimmed
    }

    mutating func prepareRestoreOnReturn() {
        pendingRestoreFriendID = lastOpenedFriendID
    }

    mutating func consumeRestoreRequest() {
        pendingRestoreFriendID = nil
    }
}
