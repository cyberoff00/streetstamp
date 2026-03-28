import XCTest
@testable import StreetStamps

final class FriendsFeedCacheBuilderTests: XCTestCase {
    func test_build_excludesEventsOlderThan30Days() {
        let now = Date()
        let withinWindow = now.addingTimeInterval(-10 * 86400)  // 10 days ago
        let outsideWindow = now.addingTimeInterval(-35 * 86400) // 35 days ago

        let friend = makeFriend(
            id: "f1",
            createdAt: outsideWindow,
            journeys: [
                makeJourney(id: "recent", cityID: "A|XX", endTime: withinWindow),
                makeJourney(id: "old", cityID: "B|XX", endTime: outsideWindow),
            ]
        )

        let cache = buildCache(friends: [friend], now: now)

        XCTAssertEqual(cache.feedEvents.count, 1, "Events older than 30 days should be excluded")
        XCTAssertEqual(cache.feedEvents.first?.journeyID, "recent")
    }

    func test_build_noPerFriendOrTotalCap() {
        let now = Date()
        // 10 friends × 10 journeys = 100 events, all within window
        let friends = (0..<10).map { friendIndex in
            makeFriend(
                id: "friend-\(friendIndex)",
                createdAt: now.addingTimeInterval(-86400),
                journeys: (0..<10).map { journeyIndex in
                    makeJourney(
                        id: "journey-\(friendIndex)-\(journeyIndex)",
                        cityID: "city-\(journeyIndex)|XX",
                        endTime: now.addingTimeInterval(-TimeInterval(friendIndex * 100 + journeyIndex))
                    )
                }
            )
        }

        let cache = buildCache(friends: friends, now: now)

        XCTAssertEqual(
            cache.feedEvents.count,
            100,
            "All events within the 30-day window should be included without per-friend or total cap"
        )
    }

    func test_build_includesSelfProfileAndSortsFriendsByRecentActivity() {
        let early = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        let olderFriend = makeFriend(
            id: "friend-older",
            createdAt: early,
            journeys: [
                makeJourney(id: "journey-older", cityID: "London|GB", endTime: early)
            ]
        )
        let newerFriend = makeFriend(
            id: "friend-newer",
            createdAt: early,
            journeys: [
                makeJourney(id: "journey-newer", cityID: "New York|US", endTime: later)
            ]
        )
        let selfProfile = makeFriend(
            id: "me",
            createdAt: early,
            journeys: [
                makeJourney(id: "journey-self", cityID: "Paris|FR", endTime: Date(timeIntervalSince1970: 3_000))
            ]
        )

        let cache = FriendsFeedCacheBuilder.build(
            friends: [olderFriend, newerFriend],
            selfProfile: selfProfile,
            lastActiveDate: { FriendListPresencePresentation.recentJourneyDate(for: $0) ?? $0.createdAt },
            formatDistance: { _ in "1.2km" },
            formatDuration: { _, _ in "0h 0m" },
            now: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(cache.sortedFriends.map(\.id), ["friend-newer", "friend-older"])
        XCTAssertEqual(cache.feedEvents.map(\.friendID), ["me", "friend-newer", "friend-older"])
        XCTAssertEqual(cache.feedProfileByID.keys.sorted(), ["friend-newer", "friend-older", "me"])
    }

    func test_build_excludesDuplicateSelfProfileFromFriendSnapshots() {
        let selfProfile = makeFriend(
            id: "me",
            createdAt: Date(timeIntervalSince1970: 1_000),
            journeys: [makeJourney(id: "journey-self", cityID: "Paris|FR", endTime: Date(timeIntervalSince1970: 2_000))]
        )

        let duplicateSelfFromFriends = makeFriend(
            id: "me",
            createdAt: Date(timeIntervalSince1970: 500),
            journeys: [makeJourney(id: "journey-duplicate", cityID: "London|GB", endTime: Date(timeIntervalSince1970: 1_500))]
        )

        let cache = FriendsFeedCacheBuilder.build(
            friends: [duplicateSelfFromFriends],
            selfProfile: selfProfile,
            lastActiveDate: { FriendListPresencePresentation.recentJourneyDate(for: $0) ?? $0.createdAt },
            formatDistance: { _ in "1.2km" },
            formatDuration: { _, _ in "0h 0m" },
            now: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(cache.feedEvents.map(\.id), ["feed_me_journey-self"])
        XCTAssertEqual(cache.feedProfileByID["me"]?.journeys.map(\.id), ["journey-self"])
    }

    func test_build_sortsByDateDescending() {
        let friend = makeFriend(
            id: "f1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            journeys: [
                makeJourney(id: "old", cityID: "A|XX", endTime: Date(timeIntervalSince1970: 1_000)),
                makeJourney(id: "mid", cityID: "B|XX", endTime: Date(timeIntervalSince1970: 2_000)),
                makeJourney(id: "new", cityID: "C|XX", endTime: Date(timeIntervalSince1970: 3_000)),
            ]
        )

        let cache = buildCache(friends: [friend])
        XCTAssertEqual(cache.feedEvents.map(\.journeyID), ["new", "mid", "old"])
    }

    func test_build_usesFriendCityDataDirectly() {
        let cards = [FriendCityCard(id: "Tokyo|JP", name: "东京", countryISO2: "JP")]
        let friend = makeFriendWithCards(
            id: "f1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            journeys: [makeJourney(id: "j1", cityID: "Tokyo|JP", endTime: Date(timeIntervalSince1970: 2_000))],
            cards: cards
        )

        let cache = buildCache(friends: [friend])
        XCTAssertEqual(cache.feedEvents.first?.location, "东京",
                       "Feed should use friend's FriendCityCard.name directly, not resolve locally")
    }

    func test_build_fallbackCityNameFromKey() {
        let friend = makeFriend(
            id: "f1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            journeys: [makeJourney(id: "j1", cityID: "Shanghai|CN", endTime: Date(timeIntervalSince1970: 2_000))]
        )

        let cache = buildCache(friends: [friend])
        XCTAssertEqual(cache.feedEvents.first?.location, "Shanghai",
                       "When no matching card, should extract name from cityKey")
    }

    func test_buildEventIDs_matchesBuildIDs() {
        let friends = (0..<5).map { fi in
            makeFriend(
                id: "f-\(fi)",
                createdAt: Date(timeIntervalSince1970: 1_000),
                journeys: (0..<5).map { ji in
                    makeJourney(
                        id: "j-\(fi)-\(ji)",
                        cityID: "c-\(ji)|XX",
                        endTime: Date(timeIntervalSince1970: 10_000 - TimeInterval(fi * 100 + ji))
                    )
                }
            )
        }

        let testNow = Date(timeIntervalSince1970: 11_000)
        let fullBuild = buildCache(friends: friends, now: testNow)
        let lightIDs = FriendsFeedCacheBuilder.buildEventIDs(friends: friends, selfProfile: nil, now: testNow)

        XCTAssertEqual(fullBuild.feedEvents.map(\.id), lightIDs,
                       "Lightweight buildEventIDs must produce the same IDs in the same order as full build")
    }

    // MARK: - Performance Tests

    func test_performance_build_50friends_100journeysEach() {
        let friends = makeLargeFriendList()
        let testNow = Date(timeIntervalSince1970: 101_000)

        measure {
            _ = FriendsFeedCacheBuilder.build(
                friends: friends,
                selfProfile: nil,
                lastActiveDate: { FriendListPresencePresentation.recentJourneyDate(for: $0) ?? $0.createdAt },
                formatDistance: { _ in "1km" },
                formatDuration: { _, _ in "0h" },
                now: testNow
            )
        }
    }

    func test_performance_buildEventIDs_50friends_100journeysEach() {
        let friends = makeLargeFriendList()
        let testNow = Date(timeIntervalSince1970: 101_000)

        measure {
            _ = FriendsFeedCacheBuilder.buildEventIDs(friends: friends, selfProfile: nil, now: testNow)
        }
    }



    // MARK: - Helpers

    private func buildCache(friends: [FriendProfileSnapshot], now: Date? = nil) -> FriendsFeedCacheSnapshot {
        FriendsFeedCacheBuilder.build(
            friends: friends,
            selfProfile: nil,
            lastActiveDate: { FriendListPresencePresentation.recentJourneyDate(for: $0) ?? $0.createdAt },
            formatDistance: { _ in "" },
            formatDuration: { _, _ in "" },
            now: now ?? Date(timeIntervalSince1970: 11_000)
        )
    }

    private func makeLargeFriendList() -> [FriendProfileSnapshot] {
        (0..<50).map { fi in
            makeFriend(
                id: "f-\(fi)",
                createdAt: Date(timeIntervalSince1970: 1_000),
                journeys: (0..<100).map { ji in
                    makeJourney(
                        id: "j-\(fi)-\(ji)",
                        cityID: "c-\(ji % 20)|XX",
                        endTime: Date(timeIntervalSince1970: 100_000 - TimeInterval(fi * 1000 + ji))
                    )
                }
            )
        }
    }

    private func makeFriend(
        id: String,
        createdAt: Date,
        journeys: [FriendSharedJourney]
    ) -> FriendProfileSnapshot {
        makeFriendWithCards(id: id, createdAt: createdAt, journeys: journeys, cards: [])
    }

    private func makeFriendWithCards(
        id: String,
        createdAt: Date,
        journeys: [FriendSharedJourney],
        cards: [FriendCityCard]
    ) -> FriendProfileSnapshot {
        FriendProfileSnapshot(
            id: id,
            handle: id,
            inviteCode: id.uppercased(),
            profileVisibility: .friendsOnly,
            displayName: id,
            bio: "",
            loadout: .defaultBoy,
            stats: ProfileStatsSnapshot(
                totalJourneys: journeys.count,
                totalDistance: journeys.reduce(0) { $0 + $1.distance },
                totalMemories: journeys.reduce(0) { $0 + $1.memories.count },
                totalUnlockedCities: cards.count
            ),
            journeys: journeys,
            unlockedCityCards: cards,
            createdAt: createdAt
        )
    }

    private func makeJourney(id: String, cityID: String, endTime: Date) -> FriendSharedJourney {
        FriendSharedJourney(
            id: id,
            title: cityID.uppercased(),
            cityID: cityID,
            activityTag: nil,
            overallMemory: nil,
            distance: 2_500,
            startTime: endTime.addingTimeInterval(-600),
            endTime: endTime,
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
    }
}
