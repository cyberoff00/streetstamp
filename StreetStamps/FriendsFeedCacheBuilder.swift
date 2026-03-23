import Foundation

struct FriendsFeedCacheSnapshot {
    let feedEvents: [FriendFeedEvent]
    let feedProfileByID: [String: FriendProfileSnapshot]
    let sortedFriends: [FriendProfileSnapshot]
    let feedLikeSignature: String
}

enum FriendsFeedCacheBuilder {
    /// Max events per friend in the feed.
    private static let maxJourneysPerFriend = 12
    /// Max total events in the feed (caps build cost, like-stats requests, etc.).
    private static let maxTotalEvents = 50

    static func build(
        friends: [FriendProfileSnapshot],
        selfProfile: FriendProfileSnapshot?,
        lastActiveDate: (FriendProfileSnapshot) -> Date,
        formatDistance: (Double) -> String,
        formatDuration: (Date?, Date?) -> String
    ) -> FriendsFeedCacheSnapshot {
        let sortedFriends = friends.sorted { lhs, rhs in
            lastActiveDate(lhs) > lastActiveDate(rhs)
        }

        let feedProfiles: [FriendProfileSnapshot]
        if let selfProfile {
            feedProfiles = [selfProfile] + sortedFriends.filter { $0.id != selfProfile.id }
        } else {
            feedProfiles = sortedFriends
        }

        let feedEvents = buildFeedEvents(
            from: feedProfiles,
            formatDistance: formatDistance,
            formatDuration: formatDuration
        )
        let feedProfileByID = Dictionary(
            feedProfiles.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let feedLikeSignature = FriendsFeedLikePresentation.statsPairs(
            from: feedEvents.map { ($0.friendID, $0.journeyID) }
        )
            .map { "\($0.friendID)|\($0.journeyID)" }
            .sorted()
            .joined(separator: ",")

        return FriendsFeedCacheSnapshot(
            feedEvents: feedEvents,
            feedProfileByID: feedProfileByID,
            sortedFriends: sortedFriends,
            feedLikeSignature: feedLikeSignature
        )
    }

    /// Lightweight: only produces event IDs for unseen-detection.
    /// Skips all title formatting and meta text.
    static func buildEventIDs(
        friends: [FriendProfileSnapshot],
        selfProfile: FriendProfileSnapshot?
    ) -> [String] {
        let feedProfiles: [FriendProfileSnapshot]
        if let selfProfile {
            feedProfiles = [selfProfile] + friends.filter { $0.id != selfProfile.id }
        } else {
            feedProfiles = friends
        }

        var stubs: [(id: String, timestamp: Date)] = []
        stubs.reserveCapacity(feedProfiles.count * maxJourneysPerFriend)

        for friend in feedProfiles {
            let eligible = friend.journeys.filter { FriendFeedLogic.isJourneyEligible($0) }
            guard !eligible.isEmpty else { continue }

            let sorted = FriendsFeedOrdering.sortJourneys(eligible)
            for journey in sorted.prefix(maxJourneysPerFriend) {
                stubs.append((
                    id: "feed_\(friend.id)_\(journey.id)",
                    timestamp: FriendFeedLogic.feedTimestamp(for: journey)
                ))
            }
        }

        return stubs
            .sorted { $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.id < $1.id }
            .prefix(maxTotalEvents)
            .map(\.id)
    }

    // MARK: - Private

    /// City identity: use the friend's published cityID directly.
    /// Display name: look up from friend's own FriendCityCard list.
    private static func friendCityKey(for journey: FriendSharedJourney) -> String {
        journey.cityID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func friendCityDisplayName(
        for journey: FriendSharedJourney,
        cards: [FriendCityCard]
    ) -> String {
        let cityKey = friendCityKey(for: journey)
        if !cityKey.isEmpty, let card = cards.first(where: { $0.id == cityKey }) {
            return card.name
        }
        // Fallback: extract city name from cityKey "Name|ISO2"
        if !cityKey.isEmpty {
            let name = cityKey.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if !name.isEmpty { return name }
        }
        return journey.title
    }

    private static func buildFeedEvents(
        from friends: [FriendProfileSnapshot],
        formatDistance: (Double) -> String,
        formatDuration: (Date?, Date?) -> String
    ) -> [FriendFeedEvent] {
        var events: [FriendFeedEvent] = []

        for friend in friends {
            let visibleJourneys = FriendsFeedOrdering.sortJourneys(
                friend.journeys.filter { FriendFeedLogic.isJourneyEligible($0) }
            )

            guard !visibleJourneys.isEmpty else { continue }

            var firstJourneyByCity: [String: String] = [:]
            for journey in visibleJourneys.reversed() {
                let key = friendCityKey(for: journey)
                if !key.isEmpty && firstJourneyByCity[key] == nil {
                    firstJourneyByCity[key] = journey.id
                }
            }

            for journey in visibleJourneys.prefix(maxJourneysPerFriend) {
                let eventDate = FriendFeedLogic.feedTimestamp(for: journey)
                let cityKey = friendCityKey(for: journey)
                let cityName = friendCityDisplayName(for: journey, cards: friend.unlockedCityCards)
                let memoryCount = journey.memories.count
                let photoCount = journey.memories.reduce(0) { $0 + $1.imageURLs.count }
                let unlockedNewCity = !cityKey.isEmpty && firstJourneyByCity[cityKey] == journey.id

                let kind: FriendFeedKind
                if unlockedNewCity {
                    kind = .city
                } else if memoryCount > 0 {
                    kind = .memory
                } else {
                    kind = .journey
                }

                let eventTitle = FriendFeedLogic.eventTitle(
                    kind: kind,
                    cityName: cityName,
                    memoryCount: memoryCount,
                    journeyTitle: journey.title
                )

                let metaText: String
                switch kind {
                case .city:
                    metaText = ""
                case .memory:
                    metaText = String(
                        format: L10n.t("friends_photos_count_format"),
                        max(photoCount, memoryCount)
                    )
                case .journey:
                    metaText = "\(formatDistance(journey.distance))  \(formatDuration(journey.startTime, journey.endTime))"
                }

                events.append(
                    FriendFeedEvent(
                        id: "feed_\(friend.id)_\(journey.id)",
                        kind: kind,
                        friendID: friend.id,
                        timestamp: eventDate,
                        journeyID: journey.id,
                        title: eventTitle,
                        location: FriendFeedLogic.locationTitle(cityName: cityName),
                        meta: metaText
                    )
                )
            }
        }

        return Array(
            events.sorted { $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.id < $1.id }
                .prefix(maxTotalEvents)
        )
    }
}
