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

        let shareableJourneys = snapshot.journeys.filter { $0.visibility != .private }
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
            let finalTitle = (title?.isEmpty == false) ? title! : route.displayCityName
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
