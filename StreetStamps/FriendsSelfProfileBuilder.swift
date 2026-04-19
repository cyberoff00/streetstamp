import Foundation

enum FriendsSelfProfileBuilder {
    static func makeSnapshot(
        remoteProfile: BackendProfileDTO?,
        fallbackUserID: String,
        fallbackDisplayName: String,
        fallbackExclusiveID: String,
        fallbackInviteCode: String,
        fallbackLoadout: RobotLoadout
    ) -> FriendProfileSnapshot? {
        if let remoteProfile {
            let resolvedExclusiveID = remoteProfile.resolvedExclusiveID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedInviteCode = remoteProfile.inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            return FriendProfileSnapshot(
                id: remoteProfile.id,
                handle: resolvedExclusiveID.isEmpty ? fallbackExclusiveID : resolvedExclusiveID,
                inviteCode: resolvedInviteCode.isEmpty ? fallbackInviteCode : resolvedInviteCode,
                profileVisibility: remoteProfile.profileVisibility ?? .friendsOnly,
                displayName: remoteProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? fallbackDisplayName
                    : remoteProfile.displayName,
                bio: remoteProfile.bio,
                loadout: (remoteProfile.loadout ?? fallbackLoadout).normalizedForCurrentAvatar(),
                stats: remoteProfile.stats ?? ProfileStatsSnapshot(
                    totalJourneys: remoteProfile.journeys.count,
                    totalDistance: remoteProfile.journeys.reduce(0) { $0 + $1.distance },
                    totalMemories: remoteProfile.journeys.reduce(0) { $0 + $1.memories.count },
                    totalUnlockedCities: remoteProfile.unlockedCityCards.count
                ),
                journeys: remoteProfile.journeys,
                unlockedCityCards: remoteProfile.unlockedCityCards,
                createdAt: remoteProfile.createdAtDate ?? Date()
            )
        }

        let uid = fallbackUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return nil }

        return FriendProfileSnapshot(
            id: uid,
            handle: fallbackExclusiveID,
            inviteCode: fallbackInviteCode,
            profileVisibility: .friendsOnly,
            displayName: fallbackDisplayName,
            bio: "",
            loadout: fallbackLoadout.normalizedForCurrentAvatar(),
            stats: .init(totalJourneys: 0, totalDistance: 0, totalMemories: 0, totalUnlockedCities: 0),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date()
        )
    }
}
