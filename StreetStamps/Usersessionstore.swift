import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LegacyGuestBinding: Codable, Hashable {
    let legacyUserID: String
    let guestID: String
    let migratedAt: Date
    let sourceDevice: String
}

struct GuestAccountBinding: Codable, Hashable {
    let guestID: String
    let accountUserID: String
    let boundAt: Date
    let sourceDevice: String
}

struct LegacyMigrationReplayReport {
    let removedMarkers: Int
    let discoveredLegacyUserIDs: [String]
}

struct FirebaseAccountState: Codable, Equatable {
    let appUserID: String
    let firebaseUID: String
    let provider: String
    let email: String?
    let emailVerified: Bool
    var cachedIDToken: String?
}

@MainActor
final class UserSessionStore: ObservableObject {
    enum Session: Equatable, Codable {
        case guest(guestID: String)
        case account(userID: String, provider: String, email: String?, accessToken: String, refreshToken: String, guestID: String)
    }

    @Published private(set) var session: Session
    @Published private(set) var firebaseAccountState: FirebaseAccountState?
    @Published private(set) var pendingMigrationFromGuestUserID: String?
    @Published private(set) var activeLocalProfileID: String

    private static let guestIDKey = "streetstamps.guest_id.v1"
    private static let activeLocalProfileIDKey = "streetstamps.active_local_profile_id.v1"
    private static let sessionDataKey = "streetstamps.session.v1"
    private static let firebaseAccountStateKey = "streetstamps.firebase_account_state.v1"
    private static let pendingGuestMigrationKey = "streetstamps.pending_guest_migration.v1"
    private static let legacyGuestBindingsKey = "streetstamps.legacy_guest_bindings.v1"
    private static let guestAccountBindingsKey = "streetstamps.guest_account_bindings.v1"
    private static let autoRecoveredGuestSourcesKey = "streetstamps.auto_recovered_guest_sources.v1"

    init() {
        let guestID = Self.loadOrCreateGuestID()
        self.activeLocalProfileID = Self.loadOrCreateActiveLocalProfileID(guestID: guestID)
        let savedPending = UserDefaults.standard.string(forKey: Self.pendingGuestMigrationKey)
        self.pendingMigrationFromGuestUserID = savedPending
        self.firebaseAccountState = Self.loadFirebaseAccountState()

        if let data = UserDefaults.standard.data(forKey: Self.sessionDataKey),
           let restored = try? JSONDecoder().decode(Session.self, from: data) {
            switch restored {
            case .guest:
                self.session = .guest(guestID: guestID)
            case .account(let userID, let provider, let email, let accessToken, let refreshToken, _):
                self.session = .account(
                    userID: userID,
                    provider: provider,
                    email: email,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    guestID: guestID
                )
            }
            return
        }

        self.session = .guest(guestID: guestID)
    }

    var currentUserID: String {
        activeLocalProfileID
    }

    var currentGuestScopedUserID: String {
        "guest_\(guestID)"
    }

    var currentAccountScopedUserID: String? {
        guard let account = accountUserID, !account.isEmpty else { return nil }
        return "account_\(account)"
    }

    var guestID: String {
        switch session {
        case .guest(let guestID): return guestID
        case .account(_, _, _, _, _, let guestID): return guestID
        }
    }

    var currentAccessToken: String? {
        switch session {
        case .guest: return nil
        case .account(_, _, _, let accessToken, _, _):
            if let firebaseToken = firebaseAccountState?.cachedIDToken,
               !firebaseToken.isEmpty {
                return firebaseToken
            }
            return accessToken
        }
    }

    var currentRefreshToken: String? {
        if firebaseAccountState != nil { return nil }
        switch session {
        case .guest: return nil
        case .account(_, _, _, _, let refreshToken, _): return refreshToken
        }
    }

    var accountUserID: String? {
        switch session {
        case .guest: return nil
        case .account(let userID, _, _, _, _, _): return userID
        }
    }

    var currentProvider: String {
        if let provider = firebaseAccountState?.provider, !provider.isEmpty {
            return provider
        }
        switch session {
        case .guest: return "guest"
        case .account(_, let provider, _, _, _, _): return provider
        }
    }

    var currentEmail: String? {
        if let email = firebaseAccountState?.email {
            return email
        }
        switch session {
        case .guest: return nil
        case .account(_, _, let email, _, _, _): return email
        }
    }

    var currentFirebaseUID: String? {
        firebaseAccountState?.firebaseUID
    }

    var currentEmailVerified: Bool {
        firebaseAccountState?.emailVerified ?? false
    }

    var isLoggedIn: Bool {
        if case .account = session { return true }
        return false
    }

    func bootstrapFileSystem() {
        do {
            let guestPaths = StoragePath(userID: currentGuestScopedUserID)
            try guestPaths.ensureBaseDirectoriesExist()
            try DataMigrator.migrateLegacyIfNeeded(paths: guestPaths)
            try DataMigrator.migrateLegacyUsersIfNeeded(
                paths: guestPaths,
                legacyUserIDs: discoverLegacyUserIDs(),
                skipUserIDs: Set([currentGuestScopedUserID, currentUserID])
            )
            recordLegacyBindings(discoverLegacyUserIDs())

            let activePaths = StoragePath(userID: activeLocalProfileID)
            try activePaths.ensureBaseDirectoriesExist()

            autoRecoverLegacySourcesIfNeeded(targetUserID: activeLocalProfileID)

        } catch {
            assertionFailure("Failed to bootstrap filesystem: \(error)")
        }
    }

    func bootstrapFileSystemAsync() async {
        let context = BootstrapContext(
            guestScopedUserID: currentGuestScopedUserID,
            activeLocalProfileID: activeLocalProfileID,
            guestID: guestID,
            accountUserID: accountUserID,
            sourceDevice: sourceDevice(),
            legacyUserIDs: discoverLegacyUserIDs()
        )
        await Self.bootstrapFileSystemWorker(context: context)
    }

    func registerWithEmail(email: String, password: String, displayName: String) async throws -> BackendRegisterResponse {
        try await BackendAPIClient.shared.register(email: email, password: password, displayName: displayName)
    }

    func loginWithEmail(email: String, password: String) async throws {
        let auth = try await BackendAPIClient.shared.login(email: email, password: password)
        applyAuth(auth)
    }

    func loginWithApple(idToken: String) async throws {
        let auth = try await BackendAPIClient.shared.loginWithApple(idToken: idToken)
        applyAuth(auth)
    }

    func resendVerificationEmail(email: String) async throws {
        try await BackendAPIClient.shared.resendVerificationEmail(email: email)
    }

    func sendPasswordReset(email: String) async throws {
        try await BackendAPIClient.shared.sendPasswordReset(email: email)
    }

    func completeFirebaseAuthentication(
        _ firebaseSession: FirebaseAuthenticatedSession,
        preserveGuestBoundary: Bool = false
    ) async throws {
        let profile = try await BackendAPIClient.shared.fetchMyProfile(token: firebaseSession.idToken)
        applyFirebaseAccountSession(
            appUserID: profile.id,
            firebaseUID: firebaseSession.snapshot.uid,
            provider: Self.appProvider(firebaseProviderID: firebaseSession.snapshot.providerID),
            email: firebaseSession.snapshot.email ?? profile.email,
            emailVerified: firebaseSession.snapshot.emailVerified,
            cachedIDToken: firebaseSession.idToken,
            preserveGuestBoundary: preserveGuestBoundary
        )
    }

    func applyAuth(_ auth: BackendAuthResponse) {
        session = .account(
            userID: auth.userId,
            provider: auth.provider,
            email: auth.email,
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken,
            guestID: guestID
        )
        firebaseAccountState = nil
        bindGuestToAccount(guestID: guestID, accountUserID: auth.userId)
        persistSession()
        persistFirebaseAccountState()
        clearPendingGuestMigrationMarker()
    }

    func applyFirebaseAccountSession(
        appUserID: String,
        firebaseUID: String,
        provider: String,
        email: String?,
        emailVerified: Bool,
        cachedIDToken: String?,
        preserveGuestBoundary: Bool = false
    ) {
        session = .account(
            userID: appUserID,
            provider: provider,
            email: email,
            accessToken: cachedIDToken ?? "",
            refreshToken: "",
            guestID: guestID
        )
        firebaseAccountState = FirebaseAccountState(
            appUserID: appUserID,
            firebaseUID: firebaseUID,
            provider: provider,
            email: email,
            emailVerified: emailVerified,
            cachedIDToken: cachedIDToken
        )
        bindGuestToAccount(guestID: guestID, accountUserID: appUserID)
        persistSession()
        persistFirebaseAccountState()
        if !preserveGuestBoundary {
            clearPendingGuestMigrationMarker()
        }
    }

    func updateCachedFirebaseIDToken(_ token: String?) {
        guard var state = firebaseAccountState else { return }
        state.cachedIDToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        firebaseAccountState = state
        persistFirebaseAccountState()

        guard case .account(let userID, let provider, let email, _, let refreshToken, let guestID) = session else {
            return
        }
        session = .account(
            userID: userID,
            provider: provider,
            email: state.email ?? email,
            accessToken: state.cachedIDToken ?? "",
            refreshToken: refreshToken,
            guestID: guestID
        )
        persistSession()
    }

    func syncFirebaseAccountState(
        firebaseUID: String,
        provider: String,
        email: String?,
        emailVerified: Bool,
        cachedIDToken: String?
    ) {
        guard let appUserID = accountUserID, !appUserID.isEmpty else { return }
        firebaseAccountState = FirebaseAccountState(
            appUserID: appUserID,
            firebaseUID: firebaseUID,
            provider: provider,
            email: email,
            emailVerified: emailVerified,
            cachedIDToken: cachedIDToken
        )
        persistFirebaseAccountState()
        updateCachedFirebaseIDToken(cachedIDToken)
    }

    @discardableResult
    func applyRefreshedAuth(_ auth: BackendAuthResponse, expectedUserID: String) -> Bool {
        guard case .account(let currentUserID, let provider, let email, _, _, let guestID) = session else {
            return false
        }
        guard currentUserID == expectedUserID, auth.userId == expectedUserID else {
            return false
        }

        session = .account(
            userID: expectedUserID,
            provider: auth.provider.isEmpty ? provider : auth.provider,
            email: auth.email ?? email,
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken,
            guestID: guestID
        )
        persistSession()
        return true
    }

    func updateAccessToken(_ accessToken: String) {
        guard case .account(let userID, let provider, let email, _, let refreshToken, let guestID) = session else {
            return
        }
        session = .account(
            userID: userID,
            provider: provider,
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            guestID: guestID
        )
        persistSession()
    }

    func logoutToGuest() {
        session = .guest(guestID: guestID)
        firebaseAccountState = nil
        persistSession()
        persistFirebaseAccountState()
    }

    func clearPendingGuestMigrationMarker() {
        pendingMigrationFromGuestUserID = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingGuestMigrationKey)
    }

    func diagnosticLegacyUserIDs() -> [String] {
        discoverLegacyUserIDs().sorted()
    }

    func forceReplayLegacyMigration() -> LegacyMigrationReplayReport {
        let guestPaths = StoragePath(userID: currentGuestScopedUserID)
        let fm = FileManager.default
        var removed = 0

        if let entries = try? fm.contentsOfDirectory(
            at: guestPaths.userRoot,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for url in entries {
                let name = url.lastPathComponent
                if name == ".migrated_v1" || name.hasPrefix(".migrated_legacy_") {
                    if (try? fm.removeItem(at: url)) != nil {
                        removed += 1
                    }
                }
            }
        }

        clearAutoRecoveryMarkers(for: currentGuestScopedUserID)
        clearAutoRecoveryMarkers(for: activeLocalProfileID)

        let legacy = discoverLegacyUserIDs()
        bootstrapFileSystem()
        return LegacyMigrationReplayReport(
            removedMarkers: removed,
            discoveredLegacyUserIDs: legacy.sorted()
        )
    }

    private func persistSession() {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionDataKey)
        }
    }

    private func persistFirebaseAccountState() {
        if let firebaseAccountState,
           let data = try? JSONEncoder().encode(firebaseAccountState) {
            UserDefaults.standard.set(data, forKey: Self.firebaseAccountStateKey)
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.firebaseAccountStateKey)
    }

    private static func loadOrCreateGuestID() -> String {
        if let stable = StableGuestIDStore.load(), !stable.isEmpty {
            UserDefaults.standard.set(stable, forKey: guestIDKey)
            return stable
        }
        if let existing = UserDefaults.standard.string(forKey: guestIDKey), !existing.isEmpty {
            StableGuestIDStore.save(existing)
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: guestIDKey)
        StableGuestIDStore.save(id)
        return id
    }

    private static func loadOrCreateActiveLocalProfileID(guestID: String) -> String {
        if let existing = UserDefaults.standard.string(forKey: activeLocalProfileIDKey),
           existing.hasPrefix("local_"),
           !existing.isEmpty {
            return existing
        }

        let id = "local_\(guestID)"
        UserDefaults.standard.set(id, forKey: activeLocalProfileIDKey)
        return id
    }

    private static func appProvider(firebaseProviderID: String) -> String {
        switch firebaseProviderID {
        case "password":
            return "email"
        case "google.com":
            return "google"
        case "apple.com":
            return "apple"
        default:
            return firebaseProviderID.isEmpty ? "firebase" : firebaseProviderID
        }
    }

    private static func loadFirebaseAccountState() -> FirebaseAccountState? {
        guard let data = UserDefaults.standard.data(forKey: firebaseAccountStateKey),
              let decoded = try? JSONDecoder().decode(FirebaseAccountState.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func discoverLegacyUserIDs() -> [String] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let journeysRoot = docs?.appendingPathComponent("Journeys", isDirectory: true)
        let appSupportUsersRoot = appSupport?
            .appendingPathComponent("StreetStamps", isDirectory: true)
        var rawCandidates: [String] = []

        if let journeysRoot,
           fm.fileExists(atPath: journeysRoot.path),
           let dirs = try? fm.contentsOfDirectory(
               at: journeysRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            let ids = dirs.compactMap { url -> String? in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return url.lastPathComponent
            }
            rawCandidates.append(contentsOf: ids)
        }

        if let appSupportUsersRoot,
           fm.fileExists(atPath: appSupportUsersRoot.path),
           let dirs = try? fm.contentsOfDirectory(
               at: appSupportUsersRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            let ids = dirs.compactMap { url -> String? in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return url.lastPathComponent
            }
            rawCandidates.append(contentsOf: ids)
        }

        rawCandidates.append(UserScope.currentUserID)
        if let idfv = currentDeviceID(), !idfv.isEmpty {
            rawCandidates.append(idfv)
        }

        let uniq = Array(Set(rawCandidates.filter { !$0.isEmpty }))
        return uniq.filter { hasLegacyData(for: $0) }
    }

    private func hasLegacyData(for legacyID: String) -> Bool {
        let fm = FileManager.default
        guard !legacyID.isEmpty else { return false }

        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let docsJourney = docs?
            .appendingPathComponent("Journeys", isDirectory: true)
            .appendingPathComponent(legacyID, isDirectory: true)

        let appSupportUserRoot = appSupport?
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent(legacyID, isDirectory: true)

        let appSupportJourneys = appSupportUserRoot?.appendingPathComponent("Journeys", isDirectory: true)
        let appSupportPhotos = appSupportUserRoot?.appendingPathComponent("Photos", isDirectory: true)
        let appSupportThumbs = appSupportUserRoot?.appendingPathComponent("Thumbnails", isDirectory: true)

        func dirHasFiles(_ url: URL?) -> Bool {
            guard let url, fm.fileExists(atPath: url.path) else { return false }
            guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return false
            }
            return !entries.isEmpty
        }

        return dirHasFiles(docsJourney)
            || dirHasFiles(appSupportJourneys)
            || dirHasFiles(appSupportPhotos)
            || dirHasFiles(appSupportThumbs)
    }

    private func recordLegacyBindings(_ legacyUserIDs: [String]) {
        guard !legacyUserIDs.isEmpty else { return }
        var existing = loadLegacyBindings()
        let now = Date()
        let device = sourceDevice()

        for legacy in legacyUserIDs {
            if existing.contains(where: { $0.legacyUserID == legacy && $0.guestID == guestID }) {
                continue
            }
            existing.append(
                LegacyGuestBinding(
                    legacyUserID: legacy,
                    guestID: guestID,
                    migratedAt: now,
                    sourceDevice: device
                )
            )
        }
        saveLegacyBindings(existing)
    }

    private func bindGuestToAccount(guestID: String, accountUserID: String) {
        var existing = loadGuestAccountBindings()
        if existing.contains(where: { $0.guestID == guestID && $0.accountUserID == accountUserID }) {
            return
        }
        existing.append(
            GuestAccountBinding(
                guestID: guestID,
                accountUserID: accountUserID,
                boundAt: Date(),
                sourceDevice: sourceDevice()
            )
        )
        saveGuestAccountBindings(existing)
    }

    private func sourceDevice() -> String {
        currentDeviceID() ?? "unknown_device"
    }

    private func currentDeviceID() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString.lowercased()
        #else
        return nil
        #endif
    }

    private func loadLegacyBindings() -> [LegacyGuestBinding] {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyGuestBindingsKey),
              let decoded = try? JSONDecoder().decode([LegacyGuestBinding].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveLegacyBindings(_ bindings: [LegacyGuestBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.legacyGuestBindingsKey)
        }
    }

    private func loadGuestAccountBindings() -> [GuestAccountBinding] {
        guard let data = UserDefaults.standard.data(forKey: Self.guestAccountBindingsKey),
              let decoded = try? JSONDecoder().decode([GuestAccountBinding].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveGuestAccountBindings(_ bindings: [GuestAccountBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.guestAccountBindingsKey)
        }
    }

    private func autoRecoverLegacySourcesIfNeeded(targetUserID: String) {
        var recoveredByTarget = loadAutoRecoveredGuestSources()
        var recoveredSources = Set(recoveredByTarget[targetUserID] ?? [])
        var changed = false

        for sourceUserID in legacyRecoverySourceUserIDs(for: targetUserID) {
            if recoveredSources.contains(sourceUserID) { continue }
            do {
                _ = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)
                recoveredSources.insert(sourceUserID)
                changed = true
            } catch {
                print("⚠️ auto recover \(sourceUserID) -> \(targetUserID) failed: \(error)")
            }
        }

        guard changed else { return }
        recoveredByTarget[targetUserID] = Array(recoveredSources).sorted()
        saveAutoRecoveredGuestSources(recoveredByTarget)
    }

    private func legacyRecoverySourceUserIDs(for targetUserID: String) -> [String] {
        scopedRecoverySourceUserIDs(
            targetUserID: targetUserID,
            guestID: guestID,
            sourceDevice: sourceDevice()
        )
    }

    private func hasRecoverableData(at userID: String) -> Bool {
        let fm = FileManager.default
        let paths = StoragePath(userID: userID)

        func dirHasEntries(_ url: URL) -> Bool {
            guard fm.fileExists(atPath: url.path),
                  let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return false
            }
            return !entries.isEmpty
        }

        return dirHasEntries(paths.journeysDir)
            || dirHasEntries(paths.photosDir)
            || dirHasEntries(paths.thumbnailsDir)
            || fm.fileExists(atPath: paths.lifelogRouteURL.path)
    }

    private func loadAutoRecoveredGuestSources() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: Self.autoRecoveredGuestSourcesKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveAutoRecoveredGuestSources(_ value: [String: [String]]) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.autoRecoveredGuestSourcesKey)
        }
    }

    private func clearAutoRecoveryMarkers(for targetUserID: String) {
        var map = loadAutoRecoveredGuestSources()
        map.removeValue(forKey: targetUserID)
        saveAutoRecoveredGuestSources(map)
    }

    private struct BootstrapContext {
        let guestScopedUserID: String
        let activeLocalProfileID: String
        let guestID: String
        let accountUserID: String?
        let sourceDevice: String
        let legacyUserIDs: [String]
    }

    nonisolated private static func bootstrapFileSystemWorker(context: BootstrapContext) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let guestPaths = StoragePath(userID: context.guestScopedUserID)
                    try guestPaths.ensureBaseDirectoriesExist()
                    try DataMigrator.migrateLegacyIfNeeded(paths: guestPaths)
                    try DataMigrator.migrateLegacyUsersIfNeeded(
                        paths: guestPaths,
                        legacyUserIDs: context.legacyUserIDs,
                        skipUserIDs: Set([context.guestScopedUserID, context.activeLocalProfileID])
                    )
                    recordLegacyBindingsWorker(
                        context.legacyUserIDs,
                        guestID: context.guestID,
                        sourceDevice: context.sourceDevice
                    )

                    let activePaths = StoragePath(userID: context.activeLocalProfileID)
                    try activePaths.ensureBaseDirectoriesExist()

                    autoRecoverLegacySourcesIfNeededWorker(
                        targetUserID: context.activeLocalProfileID
                    )

                } catch {
                    assertionFailure("Failed to bootstrap filesystem: \(error)")
                }
                continuation.resume()
            }
        }
    }

    nonisolated private static func recordLegacyBindingsWorker(
        _ legacyUserIDs: [String],
        guestID: String,
        sourceDevice: String
    ) {
        guard !legacyUserIDs.isEmpty else { return }
        var existing = loadLegacyBindingsWorker()
        let now = Date()

        for legacy in legacyUserIDs {
            if existing.contains(where: { $0.legacyUserID == legacy && $0.guestID == guestID }) {
                continue
            }
            existing.append(
                LegacyGuestBinding(
                    legacyUserID: legacy,
                    guestID: guestID,
                    migratedAt: now,
                    sourceDevice: sourceDevice
                )
            )
        }
        saveLegacyBindingsWorker(existing)
    }

    nonisolated private static func bindGuestToAccountWorker(
        guestID: String,
        accountUserID: String,
        sourceDevice: String
    ) {
        var existing = loadGuestAccountBindingsWorker()
        if existing.contains(where: { $0.guestID == guestID && $0.accountUserID == accountUserID }) {
            return
        }
        existing.append(
            GuestAccountBinding(
                guestID: guestID,
                accountUserID: accountUserID,
                boundAt: Date(),
                sourceDevice: sourceDevice
            )
        )
        saveGuestAccountBindingsWorker(existing)
    }

    nonisolated private static func autoRecoverLegacySourcesIfNeededWorker(targetUserID: String) {
        var recoveredByTarget = loadAutoRecoveredGuestSourcesWorker()
        var recoveredSources = Set(recoveredByTarget[targetUserID] ?? [])
        var changed = false

        let currentGuestID = loadOrCreateGuestIDWorker()
        let currentDevice = currentDeviceIDWorker() ?? "unknown_device"
        for sourceUserID in legacyRecoverySourceUserIDsWorker(
            for: targetUserID,
            guestID: currentGuestID,
            sourceDevice: currentDevice
        ) {
            if recoveredSources.contains(sourceUserID) { continue }
            do {
                _ = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)
                recoveredSources.insert(sourceUserID)
                changed = true
            } catch {
                print("⚠️ auto recover \(sourceUserID) -> \(targetUserID) failed: \(error)")
            }
        }

        guard changed else { return }
        recoveredByTarget[targetUserID] = Array(recoveredSources).sorted()
        saveAutoRecoveredGuestSourcesWorker(recoveredByTarget)
    }

    nonisolated private static func legacyRecoverySourceUserIDsWorker(
        for targetUserID: String,
        guestID: String,
        sourceDevice: String
    ) -> [String] {
        scopedRecoverySourceUserIDsWorker(
            targetUserID: targetUserID,
            guestID: guestID,
            sourceDevice: sourceDevice
        )
    }

    nonisolated private static func hasRecoverableDataWorker(at userID: String) -> Bool {
        let fm = FileManager.default
        let paths = StoragePath(userID: userID)

        func dirHasEntries(_ url: URL) -> Bool {
            guard fm.fileExists(atPath: url.path),
                  let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return false
            }
            return !entries.isEmpty
        }

        return dirHasEntries(paths.journeysDir)
            || dirHasEntries(paths.photosDir)
            || dirHasEntries(paths.thumbnailsDir)
            || fm.fileExists(atPath: paths.lifelogRouteURL.path)
    }

    nonisolated private static func loadLegacyBindingsWorker() -> [LegacyGuestBinding] {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyGuestBindingsKey),
              let decoded = try? JSONDecoder().decode([LegacyGuestBinding].self, from: data) else {
            return []
        }
        return decoded
    }

    nonisolated private static func saveLegacyBindingsWorker(_ bindings: [LegacyGuestBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.legacyGuestBindingsKey)
        }
    }

    nonisolated private static func loadGuestAccountBindingsWorker() -> [GuestAccountBinding] {
        guard let data = UserDefaults.standard.data(forKey: Self.guestAccountBindingsKey),
              let decoded = try? JSONDecoder().decode([GuestAccountBinding].self, from: data) else {
            return []
        }
        return decoded
    }

    nonisolated private static func saveGuestAccountBindingsWorker(_ bindings: [GuestAccountBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.guestAccountBindingsKey)
        }
    }

    nonisolated private static func loadAutoRecoveredGuestSourcesWorker() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: Self.autoRecoveredGuestSourcesKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated private static func saveAutoRecoveredGuestSourcesWorker(_ value: [String: [String]]) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.autoRecoveredGuestSourcesKey)
        }
    }

    private func scopedRecoverySourceUserIDs(
        targetUserID: String,
        guestID: String,
        sourceDevice: String
    ) -> [String] {
        let bindings = loadLegacyBindings()
            .filter { $0.guestID == guestID && $0.sourceDevice == sourceDevice }
            .map(\.legacyUserID)
        let accountBindings = loadGuestAccountBindings()
            .filter { $0.guestID == guestID && $0.sourceDevice == sourceDevice }
            .map { "account_\($0.accountUserID)" }
        let explicitCandidates = [currentGuestScopedUserID] + bindings + accountBindings
        return orderedRecoverableSourceUserIDs(
            explicitCandidates,
            targetUserID: targetUserID,
            hasRecoverableData: hasRecoverableData(at:)
        )
    }

    nonisolated private static func scopedRecoverySourceUserIDsWorker(
        targetUserID: String,
        guestID: String,
        sourceDevice: String
    ) -> [String] {
        let bindings = loadLegacyBindingsWorker()
            .filter { $0.guestID == guestID && $0.sourceDevice == sourceDevice }
            .map(\.legacyUserID)
        let accountBindings = loadGuestAccountBindingsWorker()
            .filter { $0.guestID == guestID && $0.sourceDevice == sourceDevice }
            .map { "account_\($0.accountUserID)" }
        let explicitCandidates = ["guest_\(guestID)"] + bindings + accountBindings
        return orderedRecoverableSourceUserIDsWorker(
            explicitCandidates,
            targetUserID: targetUserID,
            hasRecoverableData: hasRecoverableDataWorker(at:)
        )
    }

    private func orderedRecoverableSourceUserIDs(
        _ candidates: [String],
        targetUserID: String,
        hasRecoverableData: (String) -> Bool
    ) -> [String] {
        Self.orderedRecoverableSourceUserIDsWorker(
            candidates,
            targetUserID: targetUserID,
            hasRecoverableData: hasRecoverableData
        )
    }

    nonisolated private static func orderedRecoverableSourceUserIDsWorker(
        _ candidates: [String],
        targetUserID: String,
        hasRecoverableData: (String) -> Bool
    ) -> [String] {
        let fm = FileManager.default
        let uniqueCandidates = Array(Set(candidates)).filter { userID in
            !userID.isEmpty && userID != targetUserID
        }

        let discovered = uniqueCandidates.compactMap { userID -> (String, Date)? in
            guard hasRecoverableData(userID) else { return nil }
            let url = StoragePath(userID: userID).userRoot
            let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard fm.fileExists(atPath: url.path) else { return nil }
            return (userID, lastModified)
        }

        return discovered
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    nonisolated private static func currentDeviceIDWorker() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString.lowercased()
        #else
        return nil
        #endif
    }

    nonisolated private static func loadOrCreateGuestIDWorker() -> String {
        if let existing = UserDefaults.standard.string(forKey: guestIDKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: guestIDKey)
        return id
    }
}
