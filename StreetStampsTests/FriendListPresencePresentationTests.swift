import XCTest
@testable import StreetStamps

final class FriendListPresencePresentationTests: XCTestCase {
    func test_subtitle_usesRecentJourneyCopyWhenJourneyTimestampExists() {
        let now = Date(timeIntervalSince1970: 10_000)
        let friend = makeFriend(
            journeys: [
                FriendSharedJourney(
                    id: "journey-1",
                    title: "Morning Walk",
                    activityTag: nil,
                    overallMemory: nil,
                    distance: 1_200,
                    startTime: Date(timeIntervalSince1970: 9_400),
                    endTime: Date(timeIntervalSince1970: 9_400),
                    visibility: .friendsOnly,
                    routeCoordinates: [],
                    memories: []
                )
            ]
        )

        let text = FriendListPresencePresentation.subtitle(
            for: friend,
            now: now,
            localize: { key in
                switch key {
                case "friends_recent_journey_ago": return "Recent journey %@"
                case "friends_ago_minutes_format": return "%d min ago"
                case "friends_ago_hours_format": return "%d hr ago"
                case "friends_ago_days_format": return "%d day ago"
                case "friends_ago_weeks_format": return "%d wk ago"
                default: return key
                }
            }
        )

        XCTAssertEqual(text, "Recent journey 10 min ago")
    }

    func test_subtitle_isNilWhenFriendHasNoJourneyTimestamps() {
        let text = FriendListPresencePresentation.subtitle(
            for: makeFriend(journeys: []),
            now: Date(timeIntervalSince1970: 10_000),
            localize: { $0 }
        )

        XCTAssertNil(text)
    }

    private func makeFriend(journeys: [FriendSharedJourney]) -> FriendProfileSnapshot {
        FriendProfileSnapshot(
            id: "friend-1",
            handle: "friend-1",
            inviteCode: "FRIEND1",
            profileVisibility: .friendsOnly,
            displayName: "Friend",
            bio: "",
            loadout: .defaultBoy,
            stats: ProfileStatsSnapshot(
                totalJourneys: journeys.count,
                totalDistance: journeys.reduce(0) { $0 + $1.distance },
                totalMemories: journeys.reduce(0) { $0 + $1.memories.count },
                totalUnlockedCities: 0
            ),
            journeys: journeys,
            unlockedCityCards: [],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
