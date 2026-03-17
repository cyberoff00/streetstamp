import XCTest
@testable import StreetStamps

final class ManualDeviceRepairServiceTests: XCTestCase {
    func test_repairAllDeviceData_importsMissingJourneysFromMultipleRoots() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeJourney(id: "guest-trip", toUserID: fixture.sourceGuestUserID)
        try fixture.writeJourney(id: "account-trip", toUserID: fixture.sourceAccountUserID)

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertTrue(Set(result.importedJourneyIDs).isSuperset(of: Set(["guest-trip", "account-trip"])))
        XCTAssertTrue(Set(fixture.loadActiveJourneyIDs()).isSuperset(of: Set(["guest-trip", "account-trip"])))
    }

    func test_repairAllDeviceData_skipsDeletedJourneyIDs() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeJourney(id: "deleted-trip", toUserID: fixture.sourceGuestUserID)
        DeletedJourneyStore.record(["deleted-trip"], userID: fixture.activeUserID)

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertFalse(result.importedJourneyIDs.contains("deleted-trip"))
        XCTAssertFalse(fixture.loadActiveJourneyIDs().contains("deleted-trip"))
    }

    func test_repairAllDeviceData_ignoresFriendPreviewDirectories() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeJourney(id: "preview-trip", toUserID: fixture.sourceFriendPreviewUserID)

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertFalse(result.scannedSourceUserIDs.contains(fixture.sourceFriendPreviewUserID))
        XCTAssertFalse(result.importedJourneyIDs.contains("preview-trip"))
        XCTAssertFalse(fixture.loadActiveJourneyIDs().contains("preview-trip"))
    }

    func test_repairAllDeviceData_ignores_unrelated_guest_account_and_local_directories() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeJourney(id: "other-guest-trip", toUserID: fixture.otherGuestUserID)
        try fixture.writeJourney(id: "other-account-trip", toUserID: fixture.otherAccountUserID)
        try fixture.writeJourney(id: "other-local-trip", toUserID: fixture.otherLocalUserID)

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertFalse(result.scannedSourceUserIDs.contains(fixture.otherGuestUserID))
        XCTAssertFalse(result.scannedSourceUserIDs.contains(fixture.otherAccountUserID))
        XCTAssertFalse(result.scannedSourceUserIDs.contains(fixture.otherLocalUserID))
        XCTAssertFalse(result.importedJourneyIDs.contains("other-guest-trip"))
        XCTAssertFalse(result.importedJourneyIDs.contains("other-account-trip"))
        XCTAssertFalse(result.importedJourneyIDs.contains("other-local-trip"))
        XCTAssertFalse(fixture.loadActiveJourneyIDs().contains("other-guest-trip"))
        XCTAssertFalse(fixture.loadActiveJourneyIDs().contains("other-account-trip"))
        XCTAssertFalse(fixture.loadActiveJourneyIDs().contains("other-local-trip"))
    }

    func test_rebuildSemantics_backfillsLegacyZeroCoordinateMemoryFromJourneyTimeline() throws {
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let route = JourneyRoute(
            id: "semantic-rebuild",
            startTime: start,
            endTime: start.addingTimeInterval(120),
            distance: 100,
            coordinates: [
                CoordinateCodable(lat: 51.5007, lon: -0.1246),
                CoordinateCodable(lat: 51.5010, lon: -0.1242),
                CoordinateCodable(lat: 51.5014, lon: -0.1238)
            ],
            memories: [
                JourneyMemory(
                    id: "memory-1",
                    timestamp: start.addingTimeInterval(70),
                    title: "Legacy",
                    notes: "old payload",
                    imageData: nil,
                    coordinate: (0, 0),
                    type: .memory,
                    locationStatus: .resolved,
                    locationSource: .legacyCoordinate
                )
            ],
            trackingMode: .daily
        )

        let rebuilt = ManualDeviceRepairService.rebuildSemantics(for: route)

        XCTAssertEqual(rebuilt.memories.first?.locationStatus, .fallback)
        XCTAssertEqual(rebuilt.memories.first?.locationSource, .trackNearestByTime)
        XCTAssertNotEqual(rebuilt.memories.first?.coordinate.0, 0)
        XCTAssertNotEqual(rebuilt.memories.first?.coordinate.1, 0)
    }

    func test_repairAllDeviceData_rebuildsSemanticFieldsForExistingJourneys() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeLegacySemanticJourney(id: "legacy-semantic", toUserID: fixture.activeUserID)

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertTrue(result.rebuiltSemanticJourneyIDs.contains("legacy-semantic"))

        let repaired = try fixture.loadJourney(id: "legacy-semantic", fromUserID: fixture.activeUserID)
        XCTAssertEqual(repaired.memories.first?.locationStatus, .fallback)
        XCTAssertEqual(repaired.memories.first?.locationSource, .trackNearestByTime)
    }

    func test_repairAllDeviceData_rewritesJourneyCityIdentityFromResolvedStartCoordinate() async throws {
        let fixture = try ManualDeviceRepairFixture.make()
        try fixture.writeJourney(
            id: "hangzhou-base",
            toUserID: fixture.activeUserID,
            cityKey: "Hangzhou|CN",
            cityName: "Hangzhou",
            canonicalCity: "Hangzhou",
            currentCity: "Hangzhou",
            startCityKey: "Hangzhou|CN",
            endCityKey: "Hangzhou|CN",
            coordinates: [
                CoordinateCodable(lat: 30.2741, lon: 120.1551),
                CoordinateCodable(lat: 30.2750, lon: 120.1560)
            ]
        )
        try fixture.writeJourney(
            id: "hangzhou-preview",
            toUserID: fixture.sourceGuestUserID,
            cityKey: "WrongFriendKey|CN",
            cityName: "杭州",
            canonicalCity: "杭州",
            currentCity: "杭州",
            startCityKey: "WrongFriendKey|CN",
            endCityKey: "WrongFriendKey|CN",
            coordinates: [
                CoordinateCodable(lat: 30.2742, lon: 120.1552),
                CoordinateCodable(lat: 30.2751, lon: 120.1561)
            ]
        )

        let result = try await ManualDeviceRepairService.repairAllDeviceData(
            activeLocalProfileID: fixture.activeUserID,
            currentGuestScopedUserID: fixture.sourceGuestUserID,
            currentAccountUserID: fixture.currentAccountUserID,
            canonicalResolver: fixture.canonicalResolver
        )

        XCTAssertTrue(result.importedJourneyIDs.contains("hangzhou-preview"))
        XCTAssertTrue(result.rebuiltSemanticJourneyIDs.contains("hangzhou-preview"))

        let repaired = try fixture.loadJourney(id: "hangzhou-preview", fromUserID: fixture.activeUserID)
        XCTAssertEqual(repaired.startCityKey, "Hangzhou|CN")
        XCTAssertEqual(repaired.cityKey, "Hangzhou|CN")
        XCTAssertEqual(repaired.cityName, "Hangzhou")
        XCTAssertEqual(repaired.canonicalCity, "Hangzhou")
        XCTAssertEqual(repaired.currentCity, "Hangzhou")
        XCTAssertEqual(repaired.memories.first?.cityKey, nil)
    }
}

private struct ManualDeviceRepairFixture {
    let activeUserID: String
    let sourceGuestUserID: String
    let sourceAccountUserID: String
    let sourceFriendPreviewUserID: String
    let otherGuestUserID: String
    let otherAccountUserID: String
    let otherLocalUserID: String
    let currentAccountUserID: String

    static func make() throws -> ManualDeviceRepairFixture {
        let suffix = UUID().uuidString
        let active = "local_manual_repair_\(suffix)"
        let guest = "guest_manual_repair_\(suffix)"
        let account = "account_manual_repair_\(suffix)"
        let friendPreview = "friend_preview_manual_repair_\(suffix)"
        let otherGuest = "guest_other_\(suffix)"
        let otherAccount = "account_other_\(suffix)"
        let otherLocal = "local_other_\(suffix)"
        let fm = FileManager.default

        [active, guest, account, friendPreview, otherGuest, otherAccount, otherLocal].forEach { userID in
            try? fm.removeItem(at: StoragePath(userID: userID).userRoot)
        }
        try StoragePath(userID: active).ensureBaseDirectoriesExist()
        try StoragePath(userID: guest).ensureBaseDirectoriesExist()
        try StoragePath(userID: account).ensureBaseDirectoriesExist()
        try StoragePath(userID: friendPreview).ensureBaseDirectoriesExist()
        try StoragePath(userID: otherGuest).ensureBaseDirectoriesExist()
        try StoragePath(userID: otherAccount).ensureBaseDirectoriesExist()
        try StoragePath(userID: otherLocal).ensureBaseDirectoriesExist()

        return ManualDeviceRepairFixture(
            activeUserID: active,
            sourceGuestUserID: guest,
            sourceAccountUserID: account,
            sourceFriendPreviewUserID: friendPreview,
            otherGuestUserID: otherGuest,
            otherAccountUserID: otherAccount,
            otherLocalUserID: otherLocal,
            currentAccountUserID: String(account.dropFirst("account_".count))
        )
    }

    func writeJourney(
        id: String,
        toUserID userID: String,
        cityKey: String = "London|GB",
        cityName: String = "London",
        canonicalCity: String = "London",
        currentCity: String = "London",
        startCityKey: String? = "London|GB",
        endCityKey: String? = "London|GB",
        coordinates: [CoordinateCodable] = [
            CoordinateCodable(lat: 51.5, lon: -0.12),
            CoordinateCodable(lat: 51.6, lon: -0.13)
        ]
    ) throws {
        let paths = StoragePath(userID: userID)
        let route = JourneyRoute(
            id: id,
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            cityKey: cityKey,
            canonicalCity: canonicalCity,
            coordinates: coordinates,
            currentCity: currentCity,
            cityName: cityName,
            startCityKey: startCityKey,
            endCityKey: endCityKey
        )
        let data = try JSONEncoder().encode(route)
        try data.write(to: paths.journeysDir.appendingPathComponent("\(id).json"), options: .atomic)
        try JSONEncoder().encode([id]).write(
            to: paths.journeysDir.appendingPathComponent("index.json"),
            options: .atomic
        )
    }

    func writeLegacySemanticJourney(id: String, toUserID userID: String) throws {
        let paths = StoragePath(userID: userID)
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let route = JourneyRoute(
            id: id,
            startTime: start,
            endTime: start.addingTimeInterval(120),
            distance: 100,
            coordinates: [
                CoordinateCodable(lat: 51.5007, lon: -0.1246),
                CoordinateCodable(lat: 51.5010, lon: -0.1242),
                CoordinateCodable(lat: 51.5014, lon: -0.1238)
            ],
            memories: [
                JourneyMemory(
                    id: "memory-legacy",
                    timestamp: start.addingTimeInterval(60),
                    title: "Legacy",
                    notes: "Needs rebuild",
                    imageData: nil,
                    coordinate: (0, 0),
                    type: .memory,
                    locationStatus: .resolved,
                    locationSource: .legacyCoordinate
                )
            ],
            currentCity: "London",
            cityName: "London",
            startCityKey: "London|GB",
            endCityKey: "London|GB"
        )
        let data = try JSONEncoder().encode(route)
        try data.write(to: paths.journeysDir.appendingPathComponent("\(id).json"), options: .atomic)
        try JSONEncoder().encode([id]).write(
            to: paths.journeysDir.appendingPathComponent("index.json"),
            options: .atomic
        )
    }

    func loadActiveJourneyIDs() throws -> [String] {
        let paths = StoragePath(userID: activeUserID)
        let data = try Data(contentsOf: paths.journeysDir.appendingPathComponent("index.json"))
        return try JSONDecoder().decode([String].self, from: data)
    }

    func loadJourney(id: String, fromUserID userID: String) throws -> JourneyRoute {
        try JourneysFileStore(baseURL: StoragePath(userID: userID).journeysDir).loadJourney(id: id)
    }

    var canonicalResolver: ManualDeviceRepairService.CanonicalResolver {
        { location in
            if location.coordinate.longitude > 0 {
                return ReverseGeocodeService.CanonicalResult(
                    cityName: "Hangzhou",
                    iso2: "CN",
                    cityKey: "Hangzhou|CN",
                    level: .subAdmin,
                    parentRegionKey: "Zhejiang|CN",
                    availableLevels: [.subAdmin: "Hangzhou", .admin: "Zhejiang", .country: "China"],
                    localeIdentifier: "en_US"
                )
            }
            return ReverseGeocodeService.CanonicalResult(
                cityName: "London",
                iso2: "GB",
                cityKey: "London|GB",
                level: .subAdmin,
                parentRegionKey: "England|GB",
                availableLevels: [.subAdmin: "London", .admin: "England", .country: "United Kingdom"],
                localeIdentifier: "en_US"
            )
        }
    }
}
