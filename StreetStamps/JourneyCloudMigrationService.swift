import Foundation
import UIKit

struct JourneyMigrationReport {
    var uploadedJourneys: Int
    var uploadedMemories: Int
    var uploadedMediaFiles: Int
    var localOnlyPrivateJourneys: Int
}

enum JourneyCloudMigrationService {
    static func migrateAll(
        sessionStore: UserSessionStore,
        journeyStore: JourneyStore,
        cityCache: CityCache
    ) async throws -> JourneyMigrationReport {
        let snapshot = await MainActor.run { () -> (token: String?, uid: String, journeys: [JourneyRoute], cards: [CachedCity]) in
            (
                token: sessionStore.currentAccessToken,
                uid: sessionStore.currentUserID,
                journeys: journeyStore.journeys,
                cards: cityCache.cachedCities
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

        let payload = BackendMigrationRequest(journeys: payloadResult.journeys, unlockedCityCards: cards)
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

    private static func buildJourneyPayloads(
        journeys: [JourneyRoute],
        userID: String,
        token: String
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
                    token: token
                )
                memories.append(
                    BackendMemoryUploadDTO(
                        id: memory.id,
                        title: memory.title,
                        notes: memory.notes,
                        timestamp: memory.timestamp,
                        imageURLs: uploadedURLs
                    )
                )
                memoriesCount += 1
                uploadedMediaCount += uploadedURLs.count
            }

            out.append(
                BackendJourneyUploadDTO(
                    id: route.id,
                    title: finalTitle,
                    activityTag: route.activityTag,
                    overallMemory: route.overallMemory,
                    distance: route.distance,
                    startTime: route.startTime,
                    endTime: route.endTime,
                    visibility: route.visibility,
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
        token: String
    ) async throws -> [String] {
        guard !imagePaths.isEmpty else { return [] }

        let paths = StoragePath(userID: userID)
        var uploaded: [String] = []

        for name in imagePaths {
            let fileURL = paths.photosDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            let result = try await BackendAPIClient.shared.uploadMedia(
                token: token,
                data: data,
                fileName: fileURL.lastPathComponent,
                mimeType: mime
            )
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

        let localIDs = Set(journeyStore.journeys.map(\.id))
        let cloudOnly = profile.journeys.filter { !localIDs.contains($0.id) }
        guard !cloudOnly.isEmpty else { return 0 }

        let cards = profile.unlockedCityCards
        let imported = cloudOnly.map { cloudJourneyToRoute($0, cards: cards) }

        for route in imported {
            journeyStore.addCompletedJourney(route)
        }

        cityCache.rebuildFromJourneyStore()

        return imported.count
    }

    /// Converts a cloud FriendSharedJourney into a local JourneyRoute.
    private static func cloudJourneyToRoute(_ journey: FriendSharedJourney, cards: [FriendCityCard]) -> JourneyRoute {
        let routeCoords = journey.routeCoordinates
        let cityID = resolveCityID(for: journey, cards: cards)
        let cityCard = cards.first(where: { $0.id == cityID })
        let cityName = cityCard?.name ?? journey.title

        let fallbackCoordinate = routeCoords.first ?? CoordinateCodable(lat: 0, lon: 0)
        let memories: [JourneyMemory] = journey.memories.enumerated().map { idx, memory in
            let coord = routeCoords.isEmpty ? fallbackCoordinate : routeCoords[min(idx, routeCoords.count - 1)]
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
                type: .memory
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
            customTitle: journey.title,
            activityTag: journey.activityTag,
            overallMemory: journey.overallMemory
        )
    }

    private static func resolveCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        guard !cards.isEmpty else { return "Unknown|" }
        let normalizedTitle = journey.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if let hit = cards.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedTitle
        }) {
            return hit.id
        }
        if let fuzzy = cards.first(where: {
            let k = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return !k.isEmpty && !normalizedTitle.isEmpty && (normalizedTitle.contains(k) || k.contains(normalizedTitle))
        }) {
            return fuzzy.id
        }
        return cards[0].id
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
