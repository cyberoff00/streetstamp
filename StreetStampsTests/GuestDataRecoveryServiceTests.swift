import XCTest
@testable import StreetStamps

final class GuestDataRecoveryServiceTests: XCTestCase {
    func test_recover_defaultPolicy_keepsExistingJourneyAndLifelog() throws {
        let sourceUserID = "guest-recovery-source-\(UUID().uuidString)"
        let targetUserID = "local-recovery-target-\(UUID().uuidString)"
        let source = StoragePath(userID: sourceUserID)
        let target = StoragePath(userID: targetUserID)
        let fm = FileManager.default

        try? fm.removeItem(at: source.userRoot)
        try? fm.removeItem(at: target.userRoot)
        try source.ensureBaseDirectoriesExist()
        try target.ensureBaseDirectoriesExist()

        let sharedJourneyID = "journey-\(UUID().uuidString)"
        try writeJourney(
            id: sharedJourneyID,
            coordinatesCount: 3,
            to: source,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try writeJourney(
            id: sharedJourneyID,
            coordinatesCount: 8,
            to: target,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try writeLifelog(points: 12, to: source)
        try writeLifelog(points: 24, to: target)

        let result = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)

        XCTAssertEqual(result.mergedJourneyCount, 0)
        XCTAssertFalse(result.replacedLifelog)
        XCTAssertEqual(loadJourneyCoordinatesCount(id: sharedJourneyID, from: target), 8)
        XCTAssertEqual(loadLifelogPointsCount(from: target), 24)
    }

    func test_recover_copiesLifelogMoodFileToTargetUser() throws {
        let sourceUserID = "guest-recovery-source-\(UUID().uuidString)"
        let targetUserID = "guest-recovery-target-\(UUID().uuidString)"
        let source = StoragePath(userID: sourceUserID)
        let target = StoragePath(userID: targetUserID)
        let fm = FileManager.default

        try? fm.removeItem(at: source.userRoot)
        try? fm.removeItem(at: target.userRoot)
        try source.ensureBaseDirectoriesExist()
        try target.ensureBaseDirectoriesExist()

        let today = Calendar.current.startOfDay(for: Date())
        let moodKey = dayKey(today)
        let moodURL = source.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let payload = [moodKey: "happy"]
        let data = try JSONEncoder().encode(payload)
        try data.write(to: moodURL, options: .atomic)

        _ = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)

        let targetMoodURL = target.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let targetData = try Data(contentsOf: targetMoodURL)
        let restored = try JSONDecoder().decode([String: String].self, from: targetData)
        XCTAssertEqual(restored[moodKey], "happy")
    }

    @MainActor
    func test_applyAuth_fromGuest_doesNotLeavePendingMigrationMarker() throws {
        let store = UserSessionStore()
        store.logoutToGuest()
        store.clearPendingGuestMigrationMarker()

        let guestUserID = store.currentGuestScopedUserID
        let guestPaths = StoragePath(userID: guestUserID)
        let accountPaths = StoragePath(userID: "account_task5_auth_\(UUID().uuidString)")
        let fm = FileManager.default

        try? fm.removeItem(at: guestPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        try guestPaths.ensureBaseDirectoriesExist()
        try writeMoodFile(value: "guest-only", to: guestPaths)

        store.applyAuth(
            BackendAuthResponse(
                userId: String(accountPaths.userID.dropFirst("account_".count)),
                provider: "email",
                email: "task5@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )

        XCTAssertNil(store.pendingMigrationFromGuestUserID)
        XCTAssertFalse(fm.fileExists(atPath: accountPaths.cachesDir.appendingPathComponent("lifelog_mood.json").path))

        try? fm.removeItem(at: guestPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
    }

    @MainActor
    func test_applyAuth_switchesActiveLocalProfileIDToAccountScope() {
        let store = UserSessionStore()
        let initialLocalProfileID = store.activeLocalProfileID
        let accountUserID = "account-local-profile-\(UUID().uuidString)"

        store.applyAuth(
            BackendAuthResponse(
                userId: accountUserID,
                provider: "email",
                email: "local@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )

        XCTAssertNotEqual(store.activeLocalProfileID, initialLocalProfileID)
        XCTAssertEqual(store.activeLocalProfileID, "account_\(accountUserID)")
    }

    @MainActor
    func test_logoutToGuest_keepsAccountScopedLocalProfileID() {
        let store = UserSessionStore()
        let accountUserID = "account-local-profile-\(UUID().uuidString)"

        store.applyAuth(
            BackendAuthResponse(
                userId: accountUserID,
                provider: "email",
                email: "local@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )

        XCTAssertEqual(store.activeLocalProfileID, "account_\(accountUserID)")

        store.logoutToGuest()

        XCTAssertEqual(store.activeLocalProfileID, "account_\(accountUserID)")
        XCTAssertNil(store.accountUserID)
        XCTAssertEqual(store.reauthenticationPromptVersion, 0)
    }

    @MainActor
    func test_forcedLogout_requestsReauthenticationPrompt() {
        let store = UserSessionStore()

        store.applyAuth(
            BackendAuthResponse(
                userId: "forced-logout-\(UUID().uuidString)",
                provider: "email",
                email: "forced@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )
        XCTAssertTrue(store.isLoggedIn)
        XCTAssertEqual(store.reauthenticationPromptVersion, 0)

        store.logoutToGuest(requireReauthenticationPrompt: true)

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertEqual(store.reauthenticationPromptVersion, 1)
    }

    @MainActor
    func test_applyFirebaseAccountSession_switchesActiveLocalProfileIDToAccountScope() {
        let store = UserSessionStore()
        let initialLocalProfileID = store.activeLocalProfileID
        let accountUserID = "firebase-local-\(UUID().uuidString)"

        store.applyFirebaseAccountSession(
            appUserID: accountUserID,
            firebaseUID: "firebase-\(UUID().uuidString)",
            provider: "google",
            email: "firebase-local@example.com",
            emailVerified: true,
            cachedIDToken: "firebase-token",
            preserveGuestBoundary: false
        )

        XCTAssertNotEqual(store.activeLocalProfileID, initialLocalProfileID)
        XCTAssertEqual(store.activeLocalProfileID, "account_\(accountUserID)")
        XCTAssertEqual(store.accountUserID, accountUserID)
    }

    @MainActor
    func test_bootstrapFileSystemAsync_doesNotImportPreviouslyBoundAccountRootIntoActiveLocalProfile() async throws {
        let store = UserSessionStore()
        let localPaths = StoragePath(userID: store.activeLocalProfileID)
        let accountUserID = "bootstrap-bound-\(UUID().uuidString)"
        let accountPaths = StoragePath(userID: "account_\(accountUserID)")
        let fm = FileManager.default

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        try accountPaths.ensureBaseDirectoriesExist()
        try writeMoodFile(value: "account-seeded", to: accountPaths)

        store.applyAuth(
            BackendAuthResponse(
                userId: accountUserID,
                provider: "email",
                email: "bound@example.com",
                accessToken: "token",
                refreshToken: "refresh",
                needsProfileSetup: false
            )
        )
        store.logoutToGuest()

        await store.bootstrapFileSystemAsync()

        let localMoodURL = localPaths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        XCTAssertFalse(fm.fileExists(atPath: localMoodURL.path))

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
    }

    @MainActor
    func test_bootstrapFileSystemAsync_doesNotImportUnboundAccountRootIntoActiveLocalProfile() async throws {
        let store = UserSessionStore()
        let localPaths = StoragePath(userID: store.activeLocalProfileID)
        let accountPaths = StoragePath(userID: "account_unbound_\(UUID().uuidString)")
        let fm = FileManager.default

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        try accountPaths.ensureBaseDirectoriesExist()
        try writeMoodFile(value: "unbound-account", to: accountPaths)

        await store.bootstrapFileSystemAsync()

        let localMoodURL = localPaths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        XCTAssertFalse(fm.fileExists(atPath: localMoodURL.path))

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
    }

    @MainActor
    func test_bootstrapFileSystemAsync_forFirebaseAccount_doesNotArchiveGuestMoodIntoAccount() async throws {
        let store = UserSessionStore()
        store.logoutToGuest()
        store.clearPendingGuestMigrationMarker()

        let guestUserID = store.currentGuestScopedUserID
        let guestPaths = StoragePath(userID: guestUserID)
        let accountAppUserID = "task5_firebase_\(UUID().uuidString)"
        let accountPaths = StoragePath(userID: "account_\(accountAppUserID)")
        let fm = FileManager.default

        try? fm.removeItem(at: guestPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        try guestPaths.ensureBaseDirectoriesExist()
        try writeMoodFile(value: "stay-local", to: guestPaths)

        store.applyFirebaseAccountSession(
            appUserID: accountAppUserID,
            firebaseUID: "firebase-\(UUID().uuidString)",
            provider: "google",
            email: "firebase@example.com",
            emailVerified: true,
            cachedIDToken: "firebase-token",
            preserveGuestBoundary: false
        )

        await store.bootstrapFileSystemAsync()

        XCTAssertNil(store.pendingMigrationFromGuestUserID)
        XCTAssertFalse(fm.fileExists(atPath: accountPaths.cachesDir.appendingPathComponent("lifelog_mood.json").path))

        try? fm.removeItem(at: guestPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
    }

    @MainActor
    func test_bootstrapFileSystemAsync_doesNotImportRecoverableGuestSourceEvenWhenBindingSourceDeviceDiffers() async throws {
        let store = UserSessionStore()
        store.logoutToGuest()
        store.clearPendingGuestMigrationMarker()

        let fm = FileManager.default
        let localPaths = StoragePath(userID: store.activeLocalProfileID)
        let recoverableGuestUserID = "guest_legacy_recover_\(UUID().uuidString)"
        let recoverableGuestPaths = StoragePath(userID: recoverableGuestUserID)
        let recoveredJourneyID = "journey-\(UUID().uuidString)"

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: recoverableGuestPaths.userRoot)
        try localPaths.ensureBaseDirectoriesExist()
        try recoverableGuestPaths.ensureBaseDirectoriesExist()
        try writeJourney(
            id: recoveredJourneyID,
            coordinatesCount: 5,
            to: recoverableGuestPaths,
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
        try saveLegacyGuestBindings([
            LegacyGuestBinding(
                legacyUserID: recoverableGuestUserID,
                guestID: store.guestID,
                migratedAt: Date(),
                sourceDevice: "other-device"
            )
        ])

        await store.bootstrapFileSystemAsync()

        XCTAssertEqual(loadJourneyCoordinatesCount(id: recoveredJourneyID, from: localPaths), 0)

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: recoverableGuestPaths.userRoot)
        clearRecoveryMetadata()
    }

    @MainActor
    func test_bootstrapFileSystemAsync_doesNotImportAccountSourceWhenBindingSourceDeviceDiffers() async throws {
        let store = UserSessionStore()
        store.logoutToGuest()
        store.clearPendingGuestMigrationMarker()

        let fm = FileManager.default
        let localPaths = StoragePath(userID: store.activeLocalProfileID)
        let accountUserID = "mismatched-device-\(UUID().uuidString)"
        let accountPaths = StoragePath(userID: "account_\(accountUserID)")
        let accountJourneyID = "journey-\(UUID().uuidString)"

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        try localPaths.ensureBaseDirectoriesExist()
        try accountPaths.ensureBaseDirectoriesExist()
        try writeJourney(
            id: accountJourneyID,
            coordinatesCount: 7,
            to: accountPaths,
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_000)
        )
        try saveGuestAccountBindings([
            GuestAccountBinding(
                guestID: store.guestID,
                accountUserID: accountUserID,
                boundAt: Date(),
                sourceDevice: "other-device"
            )
        ])

        await store.bootstrapFileSystemAsync()

        XCTAssertEqual(loadJourneyCoordinatesCount(id: accountJourneyID, from: localPaths), 0)

        try? fm.removeItem(at: localPaths.userRoot)
        try? fm.removeItem(at: accountPaths.userRoot)
        clearRecoveryMetadata()
    }

    private func writeMoodFile(value: String, to paths: StoragePath) throws {
        let moodKey = dayKey(Calendar.current.startOfDay(for: Date()))
        let moodURL = paths.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let data = try JSONEncoder().encode([moodKey: value])
        try data.write(to: moodURL, options: .atomic)
    }

    private func writeLifelog(points: Int, to paths: StoragePath) throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = LifelogTestPayload(
            points: (0..<points).map { index in
                LifelogTestPayload.Point(
                    lat: 51.5 + Double(index) * 0.0001,
                    lon: -0.12 - Double(index) * 0.0001,
                    timestamp: baseDate.addingTimeInterval(Double(index) * 60)
                )
            }
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: paths.lifelogRouteURL, options: .atomic)
    }

    private func loadLifelogPointsCount(from paths: StoragePath) -> Int {
        guard let data = try? Data(contentsOf: paths.lifelogRouteURL),
              let payload = try? JSONDecoder().decode(LifelogTestPayload.self, from: data) else {
            return 0
        }
        return payload.points.count
    }

    private func writeJourney(id: String, coordinatesCount: Int, to paths: StoragePath, modifiedAt: Date) throws {
        let route = JourneyRoute(
            id: id,
            startTime: modifiedAt,
            endTime: modifiedAt.addingTimeInterval(600),
            distance: Double(coordinatesCount) * 100,
            coordinates: (0..<coordinatesCount).map { index in
                CoordinateCodable(
                    lat: 51.5 + Double(index) * 0.001,
                    lon: -0.12 - Double(index) * 0.001
                )
            }
        )
        let data = try JSONEncoder().encode(route)
        let journeyURL = paths.journeysDir.appendingPathComponent("\(id).json", isDirectory: false)
        try data.write(to: journeyURL, options: .atomic)
        try JSONEncoder().encode([id]).write(
            to: paths.journeysDir.appendingPathComponent("index.json", isDirectory: false),
            options: .atomic
        )
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: journeyURL.path)
    }

    private func loadJourneyCoordinatesCount(id: String, from paths: StoragePath) -> Int {
        let journeyURL = paths.journeysDir.appendingPathComponent("\(id).json", isDirectory: false)
        guard let data = try? Data(contentsOf: journeyURL),
              let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) else {
            return 0
        }
        return route.coordinates.count
    }

    private func dayKey(_ day: Date) -> String {
        let start = Calendar.current.startOfDay(for: day)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: start)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func saveLegacyGuestBindings(_ bindings: [LegacyGuestBinding]) throws {
        let data = try JSONEncoder().encode(bindings)
        UserDefaults.standard.set(data, forKey: "streetstamps.legacy_guest_bindings.v1")
    }

    private func saveGuestAccountBindings(_ bindings: [GuestAccountBinding]) throws {
        let data = try JSONEncoder().encode(bindings)
        UserDefaults.standard.set(data, forKey: "streetstamps.guest_account_bindings.v1")
    }

    private func clearRecoveryMetadata() {
        UserDefaults.standard.removeObject(forKey: "streetstamps.legacy_guest_bindings.v1")
        UserDefaults.standard.removeObject(forKey: "streetstamps.guest_account_bindings.v1")
        UserDefaults.standard.removeObject(forKey: "streetstamps.auto_recovered_guest_sources.v1")
    }
}

private struct LifelogTestPayload: Codable {
    struct Point: Codable {
        let lat: Double
        let lon: Double
        let timestamp: Date
    }

    let points: [Point]
}
