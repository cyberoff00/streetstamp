import Foundation
import SwiftUI

enum FriendIdentityPresentation {
    static func displayName(
        displayName: String?,
        exclusiveID: String?,
        userID: String,
        localize: (String) -> String = L10n.t
    ) -> String {
        if let displayName = normalizedHumanReadableValue(displayName) {
            return displayName
        }
        if let exclusiveID = normalizedHumanReadableValue(exclusiveID) {
            return exclusiveID
        }

        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty, !looksLikeInternalIdentifier(trimmedUserID) else {
            return localize("unknown")
        }
        return trimmedUserID
    }

    private static func normalizedHumanReadableValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !looksLikeInternalIdentifier(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func looksLikeInternalIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasPrefix("u_") || lowercased.hasPrefix("account_")
    }
}

struct FriendCityCard: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var countryISO2: String?
}

struct FriendSharedMemory: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var notes: String
    var timestamp: Date
    var imageURLs: [String]
    var latitude: Double?
    var longitude: Double?
    var locationStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, timestamp, imageURLs, latitude, longitude, locationStatus
    }

    init(
        id: String,
        title: String,
        notes: String,
        timestamp: Date,
        imageURLs: [String],
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationStatus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.timestamp = timestamp
        self.imageURLs = imageURLs
        self.latitude = latitude
        self.longitude = longitude
        self.locationStatus = locationStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        imageURLs = (try? c.decode([String].self, forKey: .imageURLs)) ?? []
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        locationStatus = try c.decodeIfPresent(String.self, forKey: .locationStatus)
    }
}

struct FriendSharedJourney: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var cityID: String?
    var activityTag: String?
    var overallMemory: String?
    var overallMemoryImageURLs: [String]
    var distance: Double
    var startTime: Date?
    var endTime: Date?
    var visibility: JourneyVisibility
    var sharedAt: Date?
    var routeCoordinates: [CoordinateCodable]
    var memories: [FriendSharedMemory]

    private enum CodingKeys: String, CodingKey {
        case id, title, cityID, cityId, activityTag, overallMemory, overallMemoryImageURLs, distance, startTime, endTime, visibility, sharedAt, routeCoordinates, coordinates, memories
    }

    init(
        id: String,
        title: String,
        cityID: String? = nil,
        activityTag: String?,
        overallMemory: String?,
        overallMemoryImageURLs: [String] = [],
        distance: Double,
        startTime: Date?,
        endTime: Date?,
        visibility: JourneyVisibility,
        sharedAt: Date? = nil,
        routeCoordinates: [CoordinateCodable],
        memories: [FriendSharedMemory]
    ) {
        self.id = id
        self.title = title
        self.cityID = cityID
        self.activityTag = activityTag
        self.overallMemory = overallMemory
        self.overallMemoryImageURLs = overallMemoryImageURLs
        self.distance = distance
        self.startTime = startTime
        self.endTime = endTime
        self.visibility = visibility
        self.sharedAt = sharedAt
        self.routeCoordinates = routeCoordinates
        self.memories = memories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Journey"
        cityID =
            (try? c.decode(String.self, forKey: .cityID))
            ?? (try? c.decode(String.self, forKey: .cityId))
        activityTag = try? c.decode(String.self, forKey: .activityTag)
        overallMemory = try? c.decode(String.self, forKey: .overallMemory)
        overallMemoryImageURLs = (try? c.decode([String].self, forKey: .overallMemoryImageURLs)) ?? []
        distance = (try? c.decode(Double.self, forKey: .distance)) ?? 0
        startTime = try? c.decode(Date.self, forKey: .startTime)
        endTime = try? c.decode(Date.self, forKey: .endTime)
        visibility = (try? c.decode(JourneyVisibility.self, forKey: .visibility)) ?? .private
        sharedAt = try? c.decode(Date.self, forKey: .sharedAt)
        routeCoordinates =
            (try? c.decode([CoordinateCodable].self, forKey: .routeCoordinates))
            ?? (try? c.decode([CoordinateCodable].self, forKey: .coordinates))
            ?? []
        memories = (try? c.decode([FriendSharedMemory].self, forKey: .memories)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(cityID, forKey: .cityID)
        try c.encodeIfPresent(activityTag, forKey: .activityTag)
        try c.encodeIfPresent(overallMemory, forKey: .overallMemory)
        if !overallMemoryImageURLs.isEmpty { try c.encode(overallMemoryImageURLs, forKey: .overallMemoryImageURLs) }
        try c.encode(distance, forKey: .distance)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(visibility, forKey: .visibility)
        try c.encodeIfPresent(sharedAt, forKey: .sharedAt)
        try c.encode(routeCoordinates, forKey: .routeCoordinates)
        try c.encode(memories, forKey: .memories)
    }
}

struct FriendProfileSnapshot: Identifiable, Codable, Hashable {
    var id: String
    var handle: String
    var inviteCode: String
    var profileVisibility: ProfileVisibility
    var displayName: String
    var bio: String
    var loadout: RobotLoadout
    var stats: ProfileStatsSnapshot
    var journeys: [FriendSharedJourney]
    var unlockedCityCards: [FriendCityCard]
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, handle, inviteCode, profileVisibility, displayName, bio, loadout, stats, journeys, unlockedCityCards, createdAt
    }

    init(
        id: String,
        handle: String,
        inviteCode: String,
        profileVisibility: ProfileVisibility,
        displayName: String,
        bio: String,
        loadout: RobotLoadout,
        stats: ProfileStatsSnapshot,
        journeys: [FriendSharedJourney],
        unlockedCityCards: [FriendCityCard],
        createdAt: Date
    ) {
        self.id = id
        self.handle = handle
        self.inviteCode = inviteCode
        self.profileVisibility = profileVisibility
        self.displayName = displayName
        self.bio = bio
        self.loadout = loadout
        self.stats = stats
        self.journeys = journeys
        self.unlockedCityCards = unlockedCityCards
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let rawDisplayName = try? c.decode(String.self, forKey: .displayName)
        bio = (try? c.decode(String.self, forKey: .bio)) ?? "Travel Enthusiastic"
        loadout = ((try? c.decode(RobotLoadout.self, forKey: .loadout)) ?? .defaultBoy).normalizedForCurrentAvatar()
        journeys = (try? c.decode([FriendSharedJourney].self, forKey: .journeys)) ?? []
        unlockedCityCards = (try? c.decode([FriendCityCard].self, forKey: .unlockedCityCards)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        inviteCode = (try? c.decode(String.self, forKey: .inviteCode)) ?? Self.fallbackInviteCode(source: id)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? Self.fallbackHandle(source: rawDisplayName ?? id)
        displayName = FriendIdentityPresentation.displayName(
            displayName: rawDisplayName,
            exclusiveID: handle,
            userID: id
        )
        profileVisibility = (try? c.decode(ProfileVisibility.self, forKey: .profileVisibility)) ?? .friendsOnly
        stats = (try? c.decode(ProfileStatsSnapshot.self, forKey: .stats)) ?? ProfileStatsSnapshot(
            totalJourneys: journeys.count,
            totalDistance: journeys.reduce(0) { $0 + $1.distance },
            totalMemories: journeys.reduce(0) { $0 + $1.memories.count },
            totalUnlockedCities: unlockedCityCards.count
        )
    }

    private static func fallbackInviteCode(source: String) -> String {
        let cleaned = source.replacingOccurrences(of: "-", with: "").uppercased()
        return String(cleaned.prefix(8))
    }

    fileprivate static func fallbackHandle(source: String) -> String {
        let cleaned = ProfileSharingSettings.normalizeHandle(source)
        if !cleaned.isEmpty { return cleaned }
        return "00000000"
    }
}

extension FriendSharedJourney {
    static func from(route: JourneyRoute) -> FriendSharedJourney {
        FriendSharedJourney(
            id: route.id,
            title: route.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (route.customTitle ?? "")
                : route.displayCityName,
            cityID: FriendJourneyCityIdentity.stableCityID(from: route),
            activityTag: route.activityTag,
            overallMemory: route.overallMemory,
            overallMemoryImageURLs: route.overallMemoryRemoteImageURLs,
            distance: route.distance,
            startTime: route.startTime,
            endTime: route.endTime,
            visibility: route.visibility,
            sharedAt: route.sharedAt,
            routeCoordinates: route.coordinates,
            memories: route.memories.map {
                FriendSharedMemory(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    timestamp: $0.timestamp,
                    imageURLs: $0.remoteImageURLs,
                    latitude: $0.locationStatus == .pending ? nil : $0.coordinate.0,
                    longitude: $0.locationStatus == .pending ? nil : $0.coordinate.1,
                    locationStatus: $0.locationStatus.rawValue
                )
            }
        )
    }
}

@MainActor
final class SocialGraphStore: ObservableObject {
    @Published private(set) var friends: [FriendProfileSnapshot] = []

    private var activeUserID: String

    init(userID: String) {
        self.activeUserID = userID
        Task { [weak self] in
            await self?.loadFromDiskAsync()
        }
    }

    func switchUser(_ userID: String) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        Task { [weak self] in
            await self?.loadFromDiskAsync()
        }
    }

    func addFriendSmart(
        displayName rawName: String,
        inviteCode rawCode: String?,
        handle rawHandle: String? = nil,
        accessToken: String?
    ) async throws {
        let maxFriends = await MembershipStore.shared.maxFriends
        if friends.count >= maxFriends {
            throw BackendAPIError.server(L10n.t("membership_gate_friends_limit"))
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = normalizedInviteCode(rawCode)
        let normalizedHandleRaw = String(rawHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalHandle = normalizedHandleRaw.isEmpty ? nil : normalizedHandleRaw
        let finalName = name.isEmpty ? nil : name

        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            throw BackendAPIError.server("后端未连接，已禁止本地伪造好友。请先配置后端地址并登录账号。")
        }

        _ = try await BackendAPIClient.shared.sendFriendRequest(
            token: token,
            displayName: finalName,
            inviteCode: normalizedCode,
            handle: finalHandle,
            note: finalName
        )
    }

    func importFriendSnapshot(_ snapshot: FriendProfileSnapshot) {
        if let idx = friends.firstIndex(where: { $0.id == snapshot.id || $0.inviteCode == snapshot.inviteCode }) {
            friends[idx] = snapshot
        } else {
            friends.insert(snapshot, at: 0)
        }
        persistToDisk()
    }

    func removeFriendSmart(_ friendID: String, accessToken: String?) async throws {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            throw BackendAPIError.server("后端未连接")
        }
        try await BackendAPIClient.shared.removeFriend(token: token, friendID: friendID)
        friends.removeAll { $0.id == friendID }
        persistToDisk()
    }

    func reloadFromBackendIfPossible(accessToken: String?) async {
        guard let mapped = await fetchFriendSnapshotsFromBackend(accessToken: accessToken) else { return }
        replaceFriends(mapped)
    }

    func refreshFriendProfileIfPossible(friendID: String, accessToken: String?) async {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else { return }
        do {
            let dto = try await BackendAPIClient.shared.fetchProfile(userID: friendID, token: token)
            importFriendSnapshot(Self.friendSnapshot(from: dto))
        } catch {
            print("❌ fetch friend profile failed:", error)
        }
    }

    func restoreFriendsIfEmpty(_ snapshots: [FriendProfileSnapshot]) {
        guard friends.isEmpty, !snapshots.isEmpty else { return }
        friends = snapshots
        persistToDisk()
    }

    func fetchFriendSnapshotsFromBackend(accessToken: String?) async -> [FriendProfileSnapshot]? {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else { return nil }
        do {
            let remote = try await BackendAPIClient.shared.fetchFriends(token: token)
            return remote.map(Self.friendSnapshot(from:))
        } catch {
            print("❌ fetch friends failed:", error)
            return nil
        }
    }

    func replaceFriends(_ snapshots: [FriendProfileSnapshot]) {
        friends = snapshots
        persistToDisk()
    }

    private var fileURL: URL {
        let paths = StoragePath(userID: activeUserID)
        return paths.cachesDir.appendingPathComponent("friends_graph_v1.json")
    }

    private func loadFromDiskAsync() async {
        let url = fileURL
        let userID = activeUserID
        let loaded: [FriendProfileSnapshot] = await Task.detached(priority: .userInitiated) {
            do {
                let paths = StoragePath(userID: userID)
                try paths.ensureBaseDirectoriesExist()
                guard FileManager.default.fileExists(atPath: url.path) else { return [] }
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([FriendProfileSnapshot].self, from: data)
            } catch {
                print("❌ SocialGraph load failed:", error)
                return []
            }
        }.value
        guard activeUserID == userID else { return }
        friends = loaded
    }

    private func persistToDisk() {
        do {
            let paths = StoragePath(userID: activeUserID)
            try paths.ensureBaseDirectoriesExist()
            let data = try JSONEncoder().encode(friends)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ SocialGraph save failed:", error)
        }
    }

    private func normalizedInviteCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let cleaned = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return cleaned.isEmpty ? nil : cleaned
    }

    static func generateInviteCode(source: String? = nil) -> String {
        let base = (source ?? UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        return String(base.prefix(8))
    }

    private static func friendSnapshot(from dto: BackendFriendDTO) -> FriendProfileSnapshot {
        let resolvedExclusiveID = dto.resolvedExclusiveID ?? FriendProfileSnapshot.fallbackHandle(source: dto.displayName)
        return FriendProfileSnapshot(
            id: dto.id,
            handle: resolvedExclusiveID,
            inviteCode: dto.inviteCode ?? generateInviteCode(source: dto.id),
            profileVisibility: dto.profileVisibility ?? .friendsOnly,
            displayName: FriendIdentityPresentation.displayName(
                displayName: dto.displayName,
                exclusiveID: resolvedExclusiveID,
                userID: dto.id
            ),
            bio: dto.bio,
            loadout: (dto.loadout ?? RobotLoadout.defaultBoy).normalizedForCurrentAvatar(),
            stats: dto.stats ?? ProfileStatsSnapshot(
                totalJourneys: dto.journeys.count,
                totalDistance: dto.journeys.reduce(0) { $0 + $1.distance },
                totalMemories: dto.journeys.reduce(0) { $0 + $1.memories.count },
                totalUnlockedCities: dto.unlockedCityCards.count
            ),
            journeys: dto.journeys,
            unlockedCityCards: dto.unlockedCityCards,
            createdAt: Date()
        )
    }
}
