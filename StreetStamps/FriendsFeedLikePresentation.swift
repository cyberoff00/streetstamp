import Foundation

enum FriendsFeedLikeActionMode: Equatable {
    case toggleLike
    case showLikers
}

enum FriendsFeedLikePresentation {
    static func statsPairs(
        from events: [(friendID: String, journeyID: String?)]
    ) -> [(friendID: String, journeyID: String)] {
        events.compactMap { event in
            guard let journeyID = event.journeyID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !journeyID.isEmpty else {
                return nil
            }
            return (event.friendID, journeyID)
        }
    }

    static func actionMode(
        currentUserID: String,
        eventFriendID: String,
        hasJourney: Bool
    ) -> FriendsFeedLikeActionMode? {
        guard hasJourney else { return nil }
        return currentUserID == eventFriendID ? .showLikers : .toggleLike
    }
}
