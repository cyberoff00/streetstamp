import Foundation

struct FriendsFeedCacheSnapshot {
    let feedEvents: [FriendFeedEvent]
    let feedProfileByID: [String: FriendProfileSnapshot]
    let sortedFriends: [FriendProfileSnapshot]
    let feedLikeSignature: String
}

enum FriendsFeedCacheBuilder {
    /// Feed time window: only show events from the last 30 days.
    static let feedWindowSeconds: TimeInterval = 30 * 24 * 3600

    static func build(
        friends: [FriendProfileSnapshot],
        selfProfile: FriendProfileSnapshot?,
        lastActiveDate: (FriendProfileSnapshot) -> Date,
        formatDistance: (Double) -> String,
        formatDuration: (Date?, Date?) -> String,
        now: Date = Date()
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

        let cutoff = now.addingTimeInterval(-feedWindowSeconds)
        let feedEvents = buildFeedEvents(
            from: feedProfiles,
            cutoff: cutoff,
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
        selfProfile: FriendProfileSnapshot?,
        now: Date = Date()
    ) -> [String] {
        let cutoff = now.addingTimeInterval(-feedWindowSeconds)
        let feedProfiles: [FriendProfileSnapshot]
        if let selfProfile {
            feedProfiles = [selfProfile] + friends.filter { $0.id != selfProfile.id }
        } else {
            feedProfiles = friends
        }

        var stubs: [(id: String, timestamp: Date)] = []

        for friend in feedProfiles {
            let eligible = friend.journeys.filter { FriendFeedLogic.isJourneyEligible($0) }
            guard !eligible.isEmpty else { continue }

            let sorted = FriendsFeedOrdering.sortJourneys(eligible)
            for journey in sorted {
                let ts = FriendFeedLogic.feedTimestamp(for: journey)
                guard ts >= cutoff else { break }
                stubs.append((
                    id: "feed_\(friend.id)_\(journey.id)",
                    timestamp: ts
                ))
            }
        }

        return stubs
            .sorted { $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.id < $1.id }
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
        cutoff: Date,
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

            for journey in visibleJourneys {
                let eventDate = FriendFeedLogic.feedTimestamp(for: journey)
                guard eventDate >= cutoff else { break }

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

        return events.sorted { $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.id < $1.id }
    }
}
