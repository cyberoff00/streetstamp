import Foundation

enum FriendsFeedNavigationPolicy {
    static func opensCurrentUserProfile(currentUserID: String, targetFriendID: String) -> Bool {
        normalizedID(currentUserID) == normalizedID(targetFriendID)
    }

    static func opensCurrentUserJourneyDetail(currentUserID: String, targetFriendID: String) -> Bool {
        normalizedID(currentUserID) == normalizedID(targetFriendID)
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
