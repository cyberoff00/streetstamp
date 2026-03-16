import XCTest
@testable import StreetStamps

private final class ThreadObservationBox: @unchecked Sendable {
    var value: Bool?
}

private final class MigrationPayloadBox: @unchecked Sendable {
    var value: BackendMigrationRequest?
}

final class JourneyCloudIncrementalSyncTests: XCTestCase {
    @MainActor
    func test_syncJourneyVisibilityChange_buildsShareablePayloadOffMainThread() async throws {
        let userID = "journey-sync-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()
        let originalBaseURL = BackendConfig.baseURLString
        BackendConfig.baseURLString = "https://example.com"
        defer {
            BackendConfig.baseURLString = originalBaseURL
            try? FileManager.default.removeItem(at: paths.userRoot)
        }

        let journeyStore = JourneyStore(paths: paths)
        let cityCache = CityCache(paths: paths, journeyStore: journeyStore)
        let sessionStore = UserSessionStore()
        sessionStore.applyAuth(
            BackendAuthResponse(
                userId: "account-\(UUID().uuidString)",
                provider: "email",
                email: "journey@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )

        let route = JourneyRoute(
            id: "journey-selected",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            distance: 3_200,
            isTooShort: false,
            cityKey: "London|GB",
            canonicalCity: "London",
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.51, lon: -0.11)
            ],
            memories: [],
            thumbnailCoordinates: [],
            countryISO2: "GB",
            currentCity: "London",
            cityName: "London",
            startCityKey: "London|GB",
            endCityKey: "London|GB",
            exploreMode: .city,
            trackingMode: .daily,
            visibility: .friendsOnly,
            customTitle: "London"
        )

        let city = CachedCity(
            id: "London|GB",
            name: "London",
            countryISO2: "GB",
            journeyIds: ["journey-selected"],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil
        )
        journeyStore.addCompletedJourney(route)
        cityCache.rebuildFromJourneyStore()
        XCTAssertEqual(cityCache.cachedCities.map(\.id), [city.id])

        let buildExpectation = expectation(description: "payload built")
        let sendExpectation = expectation(description: "migration sent")
        let observedMainThread = ThreadObservationBox()
        let sentPayload = MigrationPayloadBox()

        try await JourneyCloudMigrationService.syncJourneyVisibilityChange(
            journey: route,
            sessionStore: sessionStore,
            cityCache: cityCache,
            migrationSender: { _, payload in
                sentPayload.value = payload
                sendExpectation.fulfill()
            },
            payloadBuildObserver: {
                observedMainThread.value = Thread.isMainThread
                buildExpectation.fulfill()
            }
        )

        await fulfillment(of: [buildExpectation, sendExpectation], timeout: 1.0)
        XCTAssertEqual(observedMainThread.value, false)
        XCTAssertEqual(sentPayload.value?.journeys.map(\.id), ["journey-selected"])
    }

    func test_makeSingleJourneyPayload_includesOnlySelectedJourney() async throws {
        let route = JourneyRoute(
            id: "journey-selected",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            distance: 3_200,
            isTooShort: false,
            cityKey: "London|GB",
            canonicalCity: "London",
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.51, lon: -0.11)
            ],
            memories: [],
            thumbnailCoordinates: [],
            countryISO2: "GB",
            currentCity: "London",
            cityName: "London",
            startCityKey: "London|GB",
            endCityKey: "London|GB",
            exploreMode: .city,
            trackingMode: .daily,
            visibility: .public,
            customTitle: "London"
        )
        let cards = [
            CachedCity(
                id: "London|GB",
                name: "London",
                countryISO2: "GB",
                journeyIds: ["journey-selected"],
                explorations: 1,
                memories: 0,
                boundary: nil,
                anchor: nil,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil
            )
        ]

        let plan = try await JourneyCloudMigrationService.makeSingleJourneySyncPlan(
            journey: route,
            cachedCities: cards,
            userID: "local_device_user",
            token: "token"
        )

        XCTAssertEqual(plan.payload.journeys.map(\.id), ["journey-selected"])
        XCTAssertEqual(plan.payload.journeys.first?.cityID, "London|GB")
        XCTAssertEqual(plan.payload.removedJourneyIDs ?? [], [])
        XCTAssertEqual(plan.payload.unlockedCityCards.map(\.id), ["London|GB"])
    }

    func test_makeSingleJourneyPayload_includesSharedAt() async throws {
        let route = JourneyRoute(
            id: "journey-selected",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            distance: 3_200,
            isTooShort: false,
            cityKey: "London|GB",
            canonicalCity: "London",
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.51, lon: -0.11)
            ],
            memories: [],
            thumbnailCoordinates: [],
            countryISO2: "GB",
            currentCity: "London",
            cityName: "London",
            startCityKey: "London|GB",
            endCityKey: "London|GB",
            exploreMode: .city,
            trackingMode: .daily,
            visibility: .friendsOnly,
            sharedAt: Date(timeIntervalSince1970: 1_710_000_000),
            customTitle: "London"
        )

        let plan = try await JourneyCloudMigrationService.makeSingleJourneySyncPlan(
            journey: route,
            cachedCities: [],
            userID: "local_device_user",
            token: "token"
        )

        XCTAssertEqual(plan.payload.journeys.first?.sharedAt, Date(timeIntervalSince1970: 1_710_000_000))
    }

    func test_makeJourneyRemovalPayload_marksOnlySelectedJourneyForDeletion() {
        let cards = [
            FriendCityCard(id: "London|GB", name: "London", countryISO2: "GB")
        ]

        let payload = JourneyCloudMigrationService.makeJourneyRemovalPayload(
            journeyID: "journey-private",
            unlockedCityCards: cards
        )

        XCTAssertTrue(payload.journeys.isEmpty)
        XCTAssertEqual(payload.removedJourneyIDs, ["journey-private"])
        XCTAssertEqual(payload.unlockedCityCards.map(\.id), ["London|GB"])
        XCTAssertEqual(payload.snapshotComplete, false)
    }

    func test_makeSelfProfileSnapshot_prefersRemoteJourneysOverLocalDeviceHistory() {
        let remoteJourney = FriendSharedJourney(
            id: "remote-journey",
            title: "Published Journey",
            cityID: "London|GB",
            activityTag: nil,
            overallMemory: nil,
            distance: 4_200,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .public,
            routeCoordinates: [CoordinateCodable(lat: 51.5, lon: -0.12)],
            memories: []
        )
        let remote = BackendProfileDTO(
            id: "u_remote",
            handle: "dearka",
            inviteCode: "INVITE01",
            profileVisibility: .friendsOnly,
            displayName: "Dearka",
            bio: "Travel Enthusiastic",
            loadout: .defaultBoy,
            stats: nil,
            journeys: [remoteJourney],
            unlockedCityCards: []
        )

        let snapshot = FriendsSelfProfileBuilder.makeSnapshot(
            remoteProfile: remote,
            fallbackUserID: "u_fallback",
            fallbackDisplayName: "Explorer",
            fallbackExclusiveID: "fallback",
            fallbackInviteCode: "FALLBACK",
            fallbackLoadout: .defaultBoy
        )

        XCTAssertEqual(snapshot?.id, "u_remote")
        XCTAssertEqual(snapshot?.journeys.map(\.id), ["remote-journey"])
        XCTAssertEqual(snapshot?.displayName, "Dearka")
    }
}
