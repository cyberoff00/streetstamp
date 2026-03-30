import XCTest
@testable import StreetStamps

final class UserScopedProfileStateStoreTests: XCTestCase {
    func test_initializeCurrentUserSeedsScopedValuesFromLegacyGlobalState() throws {
        let defaults = try makeDefaults()
        let loadout = RobotLoadout(
            hairId: "hair_0009",
            upperId: "upper_0003",
            underId: "under_0005",
            hatId: "hat_001",
            glassId: "glass_001",
            accessoryIds: ["glasses_0001"],
            expressionId: "expr_0004"
        )
        defaults.set("ACCOUNT_NAME", forKey: UserScopedProfileStateStore.globalDisplayNameKey)
        defaults.set(try JSONEncoder().encode(loadout), forKey: UserScopedProfileStateStore.globalAvatarLoadoutKey)

        UserScopedProfileStateStore.initializeCurrentUser("account_123", defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: UserScopedProfileStateStore.displayNameKey(for: "account_123")),
            "ACCOUNT_NAME"
        )
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.avatarLoadoutKey(for: "account_123")),
            loadout.normalizedForCurrentAvatar()
        )
        XCTAssertEqual(defaults.string(forKey: UserScopedProfileStateStore.globalDisplayNameKey), "ACCOUNT_NAME")
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.globalAvatarLoadoutKey),
            loadout.normalizedForCurrentAvatar()
        )
    }

    func test_switchActiveUserRestoresGuestScopedStateInsteadOfKeepingAccountState() throws {
        let defaults = try makeDefaults()
        let guestID = "guest_abc"
        let accountID = "account_123"
        let guestLoadout = RobotLoadout(
            hairId: "hair_guest",
            upperId: "upper_guest",
            underId: "under_guest",
            expressionId: "expr_guest"
        )
        let accountLoadout = RobotLoadout(
            hairId: "hair_account",
            upperId: "upper_account",
            underId: "under_account",
            hatId: "hat_account",
            glassId: "glass_account",
            accessoryIds: ["hat_account"],
            expressionId: "expr_account"
        )

        defaults.set("GUEST_NAME", forKey: UserScopedProfileStateStore.displayNameKey(for: guestID))
        defaults.set(try JSONEncoder().encode(guestLoadout), forKey: UserScopedProfileStateStore.avatarLoadoutKey(for: guestID))
        defaults.set("ACCOUNT_NAME", forKey: UserScopedProfileStateStore.globalDisplayNameKey)
        defaults.set(try JSONEncoder().encode(accountLoadout), forKey: UserScopedProfileStateStore.globalAvatarLoadoutKey)

        UserScopedProfileStateStore.switchActiveUser(from: accountID, to: guestID, defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: UserScopedProfileStateStore.displayNameKey(for: accountID)),
            "ACCOUNT_NAME"
        )
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.avatarLoadoutKey(for: accountID)),
            accountLoadout.normalizedForCurrentAvatar()
        )
        XCTAssertEqual(defaults.string(forKey: UserScopedProfileStateStore.globalDisplayNameKey), "GUEST_NAME")
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.globalAvatarLoadoutKey),
            guestLoadout.normalizedForCurrentAvatar()
        )
    }

    func test_saveCurrentLoadoutPersistsGlobalScopedAndPendingState() throws {
        let defaults = try makeDefaults()
        let userID = "account_123"
        let loadout = RobotLoadout(
            hairId: "hair_pending",
            upperId: "upper_pending",
            underId: "under_pending",
            hatId: "hat_pending",
            glassId: "glass_pending",
            accessoryIds: ["hat_pending"],
            expressionId: "expr_pending"
        )

        UserScopedProfileStateStore.saveCurrentLoadout(loadout, for: userID, defaults: defaults)
        UserScopedProfileStateStore.markPendingLoadout(loadout, for: userID, defaults: defaults)

        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.globalAvatarLoadoutKey),
            loadout.normalizedForCurrentAvatar()
        )
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.avatarLoadoutKey(for: userID)),
            loadout.normalizedForCurrentAvatar()
        )
        XCTAssertEqual(
            UserScopedProfileStateStore.pendingLoadout(for: userID, defaults: defaults),
            loadout.normalizedForCurrentAvatar()
        )
    }

    func test_saveCurrentEconomyPersistsGlobalAndScopedState() throws {
        let defaults = try makeDefaults()
        let userID = "account_123"
        let economy = EquipmentEconomy(
            coins: 240,
            ownedItemsByCategory: [
                "hat": ["hat_001"],
                "glass": ["glass_001"]
            ]
        )

        UserScopedProfileStateStore.saveCurrentEconomy(economy, for: userID, defaults: defaults)

        XCTAssertEqual(
            try decodeEconomy(from: defaults, key: UserScopedProfileStateStore.globalEconomyKey),
            economy
        )
        XCTAssertEqual(
            try decodeEconomy(from: defaults, key: UserScopedProfileStateStore.economyKey(for: userID)),
            economy
        )
    }

    func test_equipmentEconomyStoreSavePersistsScopedStateForActiveUser() throws {
        let defaults = try makeDefaults()
        let userID = "account_123"
        let economy = EquipmentEconomy(
            coins: 99,
            ownedItemsByCategory: ["upper": ["upper_0003"]]
        )
        defaults.set(userID, forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)

        EquipmentEconomyStore.save(economy, defaults: defaults)

        XCTAssertEqual(
            try decodeEconomy(from: defaults, key: UserScopedProfileStateStore.globalEconomyKey),
            economy
        )
        XCTAssertEqual(
            try decodeEconomy(from: defaults, key: UserScopedProfileStateStore.economyKey(for: userID)),
            economy
        )
    }

    func test_currentWelcomeBonusGrantedUsesActiveUserScopedValue() throws {
        let defaults = try makeDefaults()
        let userID = "account_123"
        defaults.set(userID, forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)
        defaults.set(true, forKey: UserScopedProfileStateStore.globalWelcomeBonusKey)

        XCTAssertFalse(UserScopedProfileStateStore.currentWelcomeBonusGranted(defaults: defaults))

        UserScopedProfileStateStore.saveCurrentWelcomeBonusGranted(true, defaults: defaults)

        XCTAssertTrue(UserScopedProfileStateStore.currentWelcomeBonusGranted(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: UserScopedProfileStateStore.globalWelcomeBonusKey))
        XCTAssertTrue(defaults.bool(forKey: UserScopedProfileStateStore.welcomeBonusKey(for: userID)))
    }

    func test_clearPendingLoadoutRemovesOnlyPendingMarker() throws {
        let defaults = try makeDefaults()
        let userID = "account_123"
        let loadout = RobotLoadout(
            hairId: "hair_saved",
            upperId: "upper_saved",
            underId: "under_saved",
            hatId: "hat_saved",
            glassId: "glass_saved",
            accessoryIds: ["hat_saved"],
            expressionId: "expr_saved"
        )

        UserScopedProfileStateStore.saveCurrentLoadout(loadout, for: userID, defaults: defaults)
        UserScopedProfileStateStore.markPendingLoadout(loadout, for: userID, defaults: defaults)
        UserScopedProfileStateStore.clearPendingLoadout(for: userID, defaults: defaults)

        XCTAssertNil(UserScopedProfileStateStore.pendingLoadout(for: userID, defaults: defaults))
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.avatarLoadoutKey(for: userID)),
            loadout.normalizedForCurrentAvatar()
        )
        XCTAssertEqual(
            try decodeLoadout(from: defaults, key: UserScopedProfileStateStore.globalAvatarLoadoutKey),
            loadout.normalizedForCurrentAvatar()
        )
    }

    func test_profileSetupPendingMarkerPersistsPerUser() throws {
        let defaults = try makeDefaults()
        let firstUserID = "account_123"
        let secondUserID = "account_456"

        UserScopedProfileStateStore.markProfileSetupPending(for: firstUserID, defaults: defaults)

        XCTAssertTrue(UserScopedProfileStateStore.isProfileSetupPending(for: firstUserID, defaults: defaults))
        XCTAssertFalse(UserScopedProfileStateStore.isProfileSetupPending(for: secondUserID, defaults: defaults))

        UserScopedProfileStateStore.clearProfileSetupPending(for: firstUserID, defaults: defaults)

        XCTAssertFalse(UserScopedProfileStateStore.isProfileSetupPending(for: firstUserID, defaults: defaults))
    }

    func test_firstProfileSetupDecisionRejectsEmptyNicknameForConfirm() {
        XCTAssertEqual(
            FirstProfileSetupSubmission.decision(for: .confirm, nickname: "   "),
            .blocked(message: "Display name cannot be empty")
        )
    }

    func test_firstProfileSetupDecisionSkipAllowsEmptyNickname() {
        XCTAssertEqual(
            FirstProfileSetupSubmission.decision(for: .skip, nickname: "\n"),
            .submit(displayName: "")
        )
    }

    func test_firstProfileSetupDecisionTrimsNicknameBeforeSubmitting() {
        XCTAssertEqual(
            FirstProfileSetupSubmission.decision(for: .skip, nickname: "  CLAIRE  "),
            .submit(displayName: "CLAIRE")
        )
        XCTAssertEqual(
            FirstProfileSetupSubmission.decision(for: .confirm, nickname: "  CLAIRE  "),
            .submit(displayName: "CLAIRE")
        )
    }

    @MainActor
    func test_applyAuthTracksPendingProfileSetupInSessionStore() {
        let store = UserSessionStore()

        store.applyAuth(
            BackendAuthResponse(
                userId: "account_profile_setup",
                provider: "email",
                email: "setup@example.com",
                accessToken: "access-setup",
                refreshToken: "refresh-setup",
                needsProfileSetup: true
            )
        )

        XCTAssertTrue(store.requiresProfileSetup)
        XCTAssertTrue(UserScopedProfileStateStore.isProfileSetupPending(for: "account_profile_setup"))

        store.markProfileSetupCompleted()

        XCTAssertFalse(store.requiresProfileSetup)
        XCTAssertFalse(UserScopedProfileStateStore.isProfileSetupPending(for: "account_profile_setup"))
    }

    @MainActor
    func test_guestSessionRequiresProfileSetupUntilCompleted() {
        let store = UserSessionStore()

        XCTAssertTrue(store.requiresProfileSetup)
        XCTAssertTrue(UserScopedProfileStateStore.isProfileSetupPending(for: store.currentUserID))

        store.markProfileSetupCompleted()

        XCTAssertFalse(store.requiresProfileSetup)
        XCTAssertFalse(UserScopedProfileStateStore.isProfileSetupPending(for: store.currentUserID))
    }

    func test_decodeLoadoutMigratesRemovedHair009ToHair0007() throws {
        let legacyLoadout = RobotLoadout(
            hairId: "hair_009",
            upperId: "upper_0003",
            underId: "under_0005",
            hatId: "hat_004",
            glassId: "glass_004",
            accessoryIds: ["acc_004"],
            expressionId: "expr_0004"
        )

        let decoded = try JSONDecoder().decode(RobotLoadout.self, from: JSONEncoder().encode(legacyLoadout))

        XCTAssertEqual(decoded.hairId, "hair_0007")
        XCTAssertEqual(decoded.hatId, "hat_004")
        XCTAssertEqual(decoded.glassId, "glass_004")
    }

    func test_firebaseAuthSessionExposesCurrentIdentityAndToken() async throws {
        let provider = StubFirebaseAuthSessionProvider(
            snapshot: FirebaseAuthSessionSnapshot(
                uid: "firebase_123",
                email: "firebase@example.com",
                emailVerified: true,
                providerID: "google.com"
            ),
            tokens: ["firebase-token-1"]
        )
        FirebaseAuthSession.installTestingProvider(provider)
        defer { FirebaseAuthSession.resetTestingProvider() }

        let snapshot = FirebaseAuthSession.currentUser
        let token = try await FirebaseAuthSession.currentIDToken()

        XCTAssertEqual(snapshot?.uid, "firebase_123")
        XCTAssertEqual(snapshot?.email, "firebase@example.com")
        XCTAssertEqual(snapshot?.emailVerified, true)
        XCTAssertEqual(snapshot?.providerID, "google.com")
        XCTAssertEqual(token, "firebase-token-1")
    }

    func test_firebaseAuthSessionForceRefreshRequestsANewToken() async throws {
        let provider = StubFirebaseAuthSessionProvider(
            snapshot: FirebaseAuthSessionSnapshot(
                uid: "firebase_refresh",
                email: "refresh@example.com",
                emailVerified: false,
                providerID: "password"
            ),
            tokens: ["cached-token", "fresh-token"]
        )
        FirebaseAuthSession.installTestingProvider(provider)
        defer { FirebaseAuthSession.resetTestingProvider() }

        let first = try await FirebaseAuthSession.currentIDToken()
        let refreshed = try await FirebaseAuthSession.currentIDToken(forceRefresh: true)

        XCTAssertEqual(first, "cached-token")
        XCTAssertEqual(refreshed, "fresh-token")
        XCTAssertEqual(provider.forceRefreshCalls, [false, true])
    }

    @MainActor
    func test_filmCameraDropManager_firstSuccessfulJourneyShowsCenterAndMarksHistoricUnlock() throws {
        let defaults = try makeDefaults()
        defaults.set("account_camera", forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)
        let manager = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { true },
            scheduleCenterDrop: { action in action() }
        )

        manager.dropForJourney(journeyID: "journey_1")

        XCTAssertEqual(manager.phase, .center)

        let reopened = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { false },
            scheduleCenterDrop: { action in action() }
        )
        reopened.dropForJourney(journeyID: "journey_2")

        XCTAssertEqual(reopened.phase, .none)
    }

    @MainActor
    func test_filmCameraDropManager_historicUnlockRoutesSuccessfulFutureJourneysToSidebar() throws {
        let defaults = try makeDefaults()
        defaults.set("account_camera", forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)

        let firstManager = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { true },
            scheduleCenterDrop: { action in action() }
        )
        firstManager.dropForJourney(journeyID: "journey_1")
        firstManager.dismissToSidebar()

        let futureManager = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { true },
            scheduleCenterDrop: { action in action() }
        )
        futureManager.dropForJourney(journeyID: "journey_2")

        XCTAssertEqual(futureManager.phase, .sidebar)
    }

    @MainActor
    func test_filmCameraDropManager_reenteringSameJourneyKeepsSuccessfulRollWithoutRedroppingCenter() throws {
        let defaults = try makeDefaults()
        defaults.set("account_camera", forKey: UserScopedProfileStateStore.activeLocalProfileIDKey)
        let firstManager = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { true },
            scheduleCenterDrop: { action in action() }
        )
        firstManager.dropForJourney(journeyID: "journey_same")
        firstManager.dismissToSidebar()

        let reopened = FilmCameraDropManager(
            defaults: defaults,
            randomRoll: { false },
            scheduleCenterDrop: { action in action() }
        )
        reopened.dropForJourney(journeyID: "journey_same")

        XCTAssertEqual(reopened.phase, .sidebar)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UserScopedProfileStateStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func decodeLoadout(from defaults: UserDefaults, key: String) throws -> RobotLoadout {
        guard let data = defaults.data(forKey: key) else {
            XCTFail("Missing loadout data for key \(key)")
            return .defaultBoy
        }
        return try JSONDecoder().decode(RobotLoadout.self, from: data)
    }

    private func decodeEconomy(from defaults: UserDefaults, key: String) throws -> EquipmentEconomy {
        let data = try XCTUnwrap(defaults.data(forKey: key))
        return try JSONDecoder().decode(EquipmentEconomy.self, from: data)
    }
}

private final class StubFirebaseAuthSessionProvider: FirebaseAuthSessionProviding {
    let snapshot: FirebaseAuthSessionSnapshot?
    private var queuedTokens: [String]
    private(set) var forceRefreshCalls: [Bool] = []

    init(snapshot: FirebaseAuthSessionSnapshot?, tokens: [String]) {
        self.snapshot = snapshot
        self.queuedTokens = tokens
    }

    func currentUser() -> FirebaseAuthSessionSnapshot? {
        snapshot
    }

    func currentIDToken(forceRefresh: Bool) async throws -> String? {
        forceRefreshCalls.append(forceRefresh)
        if queuedTokens.isEmpty { return nil }
        return queuedTokens.removeFirst()
    }
}
