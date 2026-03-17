import Foundation
import UIKit

struct JourneyMigrationReport {
    var uploadedJourneys: Int
    var uploadedMemories: Int
    var uploadedMediaFiles: Int
    var localOnlyPrivateJourneys: Int
}

struct JourneyIncrementalSyncPlan {
    var payload: BackendMigrationRequest
    var uploadedMemories: Int
    var uploadedMediaFiles: Int
}

enum JourneyCloudMigrationService {
    typealias MediaUploader = @Sendable (_ token: String, _ data: Data, _ fileName: String, _ mimeType: String) async throws -> BackendMediaUploadResponse
    typealias MigrationSender = @Sendable (_ token: String, _ payload: BackendMigrationRequest) async throws -> Void
    typealias PayloadBuildObserver = @Sendable () -> Void

    private static let liveMediaUploader: MediaUploader = { token, data, fileName, mimeType in
        try await BackendAPIClient.shared.uploadMedia(
            token: token,
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    private static let liveMigrationSender: MigrationSender = { token, payload in
        try await BackendAPIClient.shared.migrateJourneys(token: token, payload: payload)
    }

    static func shouldMergeDownloadedProfile(expectedAccountUserID: String?, remoteProfileID: String) -> Bool {
        let expected = expectedAccountUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remote = remoteProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty, !remote.isEmpty else { return false }
        return expected == remote
    }

    static func migrateAll(
        sessionStore: UserSessionStore,
        journeyStore: JourneyStore,
        cityCache: CityCache
    ) async throws -> JourneyMigrationReport {
        let snapshot = await MainActor.run { () -> (token: String?, uid: String, journeys: [JourneyRoute], cards: [CachedCity], hasLoaded: Bool) in
            (
                token: sessionStore.currentAccessToken,
                uid: sessionStore.currentUserID,
                journeys: journeyStore.journeys,
                cards: cityCache.cachedCities,
                hasLoaded: journeyStore.hasLoaded
            )
        }

        guard let token = snapshot.token, !token.isEmpty else {
            throw BackendAPIError.unauthorized
        }

        let currentLoadout = AvatarLoadoutStore.load()
        _ = try? await BackendAPIClient.shared.updateLoadout(token: token, loadout: currentLoadout)

        let shareableJourneys = snapshot.journeys.filter { $0.visibility == .public || $0.visibility == .friendsOnly }
        let privateJourneysCount = snapshot.journeys.count - shareableJourneys.count

        let payloadResult = try await buildJourneyPayloads(
            journeys: shareableJourneys,
            userID: snapshot.uid,
            token: token
        )

        let cards = snapshot.cards
            .filter { !($0.isTemporary ?? false) }
            .map { FriendCityCard(id: $0.id, name: $0.name, countryISO2: $0.countryISO2) }

        let removedJourneyIDs = try await removedRemoteJourneyIDsIfNeeded(
            token: token,
            hasLoaded: snapshot.hasLoaded,
            localShareableJourneys: payloadResult.journeys
        )

        let payload = BackendMigrationRequest(
            journeys: payloadResult.journeys,
            unlockedCityCards: cards,
            removedJourneyIDs: removedJourneyIDs.isEmpty ? nil : removedJourneyIDs,
            snapshotComplete: false
        )
        try await BackendAPIClient.shared.migrateJourneys(token: token, payload: payload)

        await MainActor.run {
            sessionStore.clearPendingGuestMigrationMarker()
        }

        return JourneyMigrationReport(
            uploadedJourneys: payloadResult.journeys.count,
            uploadedMemories: payloadResult.memoriesCount,
            uploadedMediaFiles: payloadResult.uploadedMediaCount,
            localOnlyPrivateJourneys: privateJourneysCount
        )
    }

    static func makeSingleJourneySyncPlan(
        journey: JourneyRoute,
        cachedCities: [CachedCity],
        userID: String,
        token: String,
        mediaUploader: MediaUploader = liveMediaUploader
    ) async throws -> JourneyIncrementalSyncPlan {
        let payloadResult = try await buildJourneyPayloads(
            journeys: [journey],
            userID: userID,
            token: token,
            mediaUploader: mediaUploader
        )
        let cards = cachedCities
            .filter { !($0.isTemporary ?? false) }
            .map { FriendCityCard(id: $0.id, name: $0.name, countryISO2: $0.countryISO2) }

        return JourneyIncrementalSyncPlan(
            payload: BackendMigrationRequest(
                journeys: payloadResult.journeys,
                unlockedCityCards: cards,
                removedJourneyIDs: nil,
                snapshotComplete: false
            ),
            uploadedMemories: payloadResult.memoriesCount,
            uploadedMediaFiles: payloadResult.uploadedMediaCount
        )
    }

    static func makeJourneyRemovalPayload(
        journeyID: String,
        unlockedCityCards: [FriendCityCard]
    ) -> BackendMigrationRequest {
        BackendMigrationRequest(
            journeys: [],
            unlockedCityCards: unlockedCityCards,
            removedJourneyIDs: [journeyID],
            snapshotComplete: false
        )
    }

    @MainActor
    static func syncJourneyVisibilityChange(
        journey: JourneyRoute,
        sessionStore: UserSessionStore,
        cityCache: CityCache,
        migrationSender: @escaping MigrationSender = liveMigrationSender,
        mediaUploader: @escaping MediaUploader = liveMediaUploader,
        payloadBuildObserver: PayloadBuildObserver? = nil
    ) async throws {
        guard BackendConfig.isEnabled else { return }

        let snapshot = await MainActor.run {
            (
                token: sessionStore.currentAccessToken,
                userID: sessionStore.currentUserID,
                cards: cityCache.cachedCities
            )
        }

        guard let token = snapshot.token, !token.isEmpty else {
            throw BackendAPIError.unauthorized
        }

        let cards = snapshot.cards
            .filter { !($0.isTemporary ?? false) }
            .map { FriendCityCard(id: $0.id, name: $0.name, countryISO2: $0.countryISO2) }

        let payload: BackendMigrationRequest
        if journey.visibility == .public || journey.visibility == .friendsOnly {
            let plan = try await Task.detached(priority: .userInitiated) {
                payloadBuildObserver?()
                return try await makeSingleJourneySyncPlan(
                    journey: journey,
                    cachedCities: snapshot.cards,
                    userID: snapshot.userID,
                    token: token,
                    mediaUploader: mediaUploader
                )
            }.value
            payload = plan.payload
        } else {
            payload = makeJourneyRemovalPayload(
                journeyID: journey.id,
                unlockedCityCards: cards
            )
        }

        try await migrationSender(token, payload)
    }

    private static func removedRemoteJourneyIDsIfNeeded(
        token: String,
        hasLoaded: Bool,
        localShareableJourneys: [BackendJourneyUploadDTO]
    ) async throws -> [String] {
        guard hasLoaded else { return [] }

        let remoteProfile: BackendProfileDTO
        do {
            remoteProfile = try await BackendAPIClient.shared.fetchMyProfile(token: token)
        } catch {
            // If the client cannot confirm the current remote snapshot, prefer
            // a merge-only sync over a potentially destructive delete.
            return []
        }

        let localIDs = Set(localShareableJourneys.map(\.id))
        let remoteIDs = Set(remoteProfile.journeys.map(\.id))
        return Array(remoteIDs.subtracting(localIDs)).sorted()
    }

    private static func buildJourneyPayloads(
        journeys: [JourneyRoute],
        userID: String,
        token: String,
        mediaUploader: MediaUploader = liveMediaUploader
    ) async throws -> (journeys: [BackendJourneyUploadDTO], memoriesCount: Int, uploadedMediaCount: Int) {
        var out: [BackendJourneyUploadDTO] = []
        var memoriesCount = 0
        var uploadedMediaCount = 0

        for route in journeys {
            let title = route.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = (title?.isEmpty == false) ? (title ?? route.displayCityName) : route.displayCityName
            let routeCoordinates = route.coordinates.isEmpty ? route.thumbnailCoordinates : route.coordinates

            var memories: [BackendMemoryUploadDTO] = []
            for memory in route.memories {
                let uploadedURLs = try await uploadMemoryImagesIfNeeded(
                    imagePaths: memory.imagePaths,
                    userID: userID,
                    token: token,
                    mediaUploader: mediaUploader
                )
                memories.append(
                    BackendMemoryUploadDTO(
                        id: memory.id,
                        title: memory.title,
                        notes: memory.notes,
                        timestamp: memory.timestamp,
                        imageURLs: uploadedURLs,
                        latitude: memory.locationStatus == .pending ? nil : memory.coordinate.0,
                        longitude: memory.locationStatus == .pending ? nil : memory.coordinate.1,
                        locationStatus: memory.locationStatus.rawValue
                    )
                )
                memoriesCount += 1
                uploadedMediaCount += uploadedURLs.count
            }

            out.append(
                BackendJourneyUploadDTO(
                    id: route.id,
                    title: finalTitle,
                    cityID: FriendJourneyCityIdentity.stableCityID(from: route),
                    activityTag: route.activityTag,
                    overallMemory: route.overallMemory,
                    distance: route.distance,
                    startTime: route.startTime,
                    endTime: route.endTime,
                    visibility: route.visibility,
                    sharedAt: route.sharedAt,
                    routeCoordinates: routeCoordinates,
                    memories: memories
                )
            )
        }

        return (out, memoriesCount, uploadedMediaCount)
    }

    private static func uploadMemoryImagesIfNeeded(
        imagePaths: [String],
        userID: String,
        token: String,
        mediaUploader: MediaUploader = liveMediaUploader
    ) async throws -> [String] {
        guard !imagePaths.isEmpty else { return [] }

        let paths = StoragePath(userID: userID)
        var uploaded: [String] = []

        for name in imagePaths {
            let fileURL = paths.photosDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            let result = try await mediaUploader(token, data, fileURL.lastPathComponent, mime)
            uploaded.append(result.url)
        }

        return uploaded
    }

    // MARK: - Download & Merge (Cloud → Local)

    /// Fetches the user's own profile from the backend (which includes uploaded journeys)
    /// and merges any cloud-only journeys into the local JourneyStore.
    /// Returns the number of newly imported journeys.
    @MainActor
    static func downloadAndMerge(
        sessionStore: UserSessionStore,
        journeyStore: JourneyStore,
        cityCache: CityCache
    ) async throws -> Int {
        guard BackendConfig.isEnabled else { return 0 }

        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            return 0
        }

        let profile = try await BackendAPIClient.shared.fetchMyProfile(token: token)
        guard shouldMergeDownloadedProfile(
            expectedAccountUserID: sessionStore.accountUserID,
            remoteProfileID: profile.id
        ) else {
            print("🚫 Refused cloud merge due to account mismatch. expected=\(sessionStore.accountUserID ?? "nil") remote=\(profile.id)")
            return 0
        }

        let localIDs = Set(journeyStore.journeys.map(\.id))
        let cloudOnly = profile.journeys.filter { !localIDs.contains($0.id) }
        guard !cloudOnly.isEmpty else { return 0 }

        let cards = profile.unlockedCityCards
        let imported = cloudOnly.map { cloudJourneyToRoute($0, cards: cards) }

        for route in imported {
            journeyStore.addCompletedJourney(route)
        }

        let sourceEntries = Dictionary(
            uniqueKeysWithValues: imported.map { ($0.id, JourneyRepairSource.accountCache(accountUserID: profile.id)) }
        )
        JourneyRepairSourceStore.merge(sourceEntries, userID: sessionStore.activeLocalProfileID)

        cityCache.rebuildFromJourneyStore()

        return imported.count
    }

    /// Converts a cloud FriendSharedJourney into a local JourneyRoute.
    private static func cloudJourneyToRoute(_ journey: FriendSharedJourney, cards: [FriendCityCard]) -> JourneyRoute {
        let routeCoords = journey.routeCoordinates
        let cityID = FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards)
        let collectionKey = FriendJourneyCityIdentity.resolveCollectionKey(for: journey, cards: cards)
        let cityCard = cards.first(where: { $0.id == cityID })
        let cityName = CityDisplayResolver.title(
            for: collectionKey,
            fallbackTitle: CityCollectionResolver.configuredTitle(for: collectionKey) ?? cityCard?.name ?? journey.title
        )

        let fallbackCoordinate = routeCoords.first ?? CoordinateCodable(lat: 0, lon: 0)
        let memories: [JourneyMemory] = journey.memories.enumerated().map { idx, memory in
            let explicitCoordinate: CoordinateCodable? = {
                guard let latitude = memory.latitude, let longitude = memory.longitude else { return nil }
                return CoordinateCodable(lat: latitude, lon: longitude)
            }()
            let coord = explicitCoordinate ?? (routeCoords.isEmpty ? fallbackCoordinate : routeCoords[min(idx, routeCoords.count - 1)])
            let status = JourneyMemoryLocationStatus(rawValue: memory.locationStatus ?? "")
                ?? (explicitCoordinate == nil ? .resolved : .fallback)
            let source: JourneyMemoryLocationSource = {
                if status == .pending { return .pending }
                if explicitCoordinate != nil && status == .fallback { return .trackNearestByTime }
                return .legacyCoordinate
            }()
            return JourneyMemory(
                id: memory.id,
                timestamp: memory.timestamp,
                title: memory.title,
                notes: memory.notes,
                imageData: nil,
                imagePaths: [],
                remoteImageURLs: memory.imageURLs,
                cityKey: cityID,
                cityName: cityName,
                coordinate: (coord.lat, coord.lon),
                type: .memory,
                locationStatus: status,
                locationSource: source
            )
        }

        return JourneyRoute(
            id: journey.id,
            startTime: journey.startTime,
            endTime: journey.endTime,
            distance: max(0, journey.distance),
            elevationGain: 0,
            elevationLoss: 0,
            isTooShort: false,
            cityKey: cityID,
            canonicalCity: cityName,
            coordinates: routeCoords,
            memories: memories,
            thumbnailCoordinates: routeCoords,
            countryISO2: cityCard?.countryISO2,
            currentCity: cityName,
            cityName: cityName,
            startCityKey: cityID,
            endCityKey: cityID,
            exploreMode: .city,
            trackingMode: .daily,
            visibility: journey.visibility,
            sharedAt: journey.sharedAt,
            customTitle: journey.title,
            activityTag: journey.activityTag,
            overallMemory: journey.overallMemory
        )
    }

    // MARK: - Helpers

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
