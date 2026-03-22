import Foundation

enum FriendsFeedOrdering {
    struct EventIdentity: Equatable {
        let id: String
        let timestamp: Date
    }

    static func sortJourneys(_ journeys: [FriendSharedJourney]) -> [FriendSharedJourney] {
        journeys.sorted { lhs, rhs in
            let lhsTimestamp = FriendFeedLogic.feedTimestamp(for: lhs)
            let rhsTimestamp = FriendFeedLogic.feedTimestamp(for: rhs)
            if lhsTimestamp != rhsTimestamp {
                return lhsTimestamp > rhsTimestamp
            }
            return lhs.id < rhs.id
        }
    }

    static func sortEvents(_ events: [EventIdentity]) -> [EventIdentity] {
        events.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }
}
