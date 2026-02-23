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

@MainActor
final class UserSessionStore: ObservableObject {
    enum Session: Equatable, Codable {
        case guest(guestID: String)
        case account(userID: String, provider: String, email: String?, accessToken: String, refreshToken: String, guestID: String)
    }

    @Published private(set) var session: Session
    @Published private(set) var pendingMigrationFromGuestUserID: String?

    private static let guestIDKey = "streetstamps.guest_id.v1"
    private static let sessionDataKey = "streetstamps.session.v1"
    private static let pendingGuestMigrationKey = "streetstamps.pending_guest_migration.v1"
    private static let legacyGuestBindingsKey = "streetstamps.legacy_guest_bindings.v1"
    private static let guestAccountBindingsKey = "streetstamps.guest_account_bindings.v1"
    private static let autoRecoveredGuestSourcesKey = "streetstamps.auto_recovered_guest_sources.v1"

    init() {
        let guestID = Self.loadOrCreateGuestID()
        let savedPending = UserDefaults.standard.string(forKey: Self.pendingGuestMigrationKey)
        self.pendingMigrationFromGuestUserID = savedPending

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
        if let account = accountUserID, !account.isEmpty {
            return "account_\(account)"
        }
        return currentGuestScopedUserID
    }

    var currentGuestScopedUserID: String {
        "guest_\(guestID)"
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
        case .account(_, _, _, let accessToken, _, _): return accessToken
        }
    }

    var currentRefreshToken: String? {
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
        switch session {
        case .guest: return "guest"
        case .account(_, let provider, _, _, _, _): return provider
        }
    }

    var currentEmail: String? {
        switch session {
        case .guest: return nil
        case .account(_, _, let email, _, _, _): return email
        }
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

            let activePaths = StoragePath(userID: currentUserID)
            try activePaths.ensureBaseDirectoriesExist()

            // Guest-first restore: when reinstall/create-new-guest happens, pull data from any older guest_* roots on this device.
            autoRecoverGuestSourcesIfNeeded(targetUserID: currentGuestScopedUserID, accountUserID: nil)

            // Backfill: if user is already logged in, ensure this device's guest data is also bound/archived to account.
            if let account = accountUserID, !account.isEmpty {
                let targetAccountUserID = "account_\(account)"
                do {
                    _ = try GuestDataRecoveryService.recover(
                        from: currentGuestScopedUserID,
                        to: targetAccountUserID
                    )
                } catch {
                    print("⚠️ bootstrap guest -> account archive failed: \(error)")
                }
                bindGuestToAccount(guestID: guestID, accountUserID: account)
                autoRecoverGuestSourcesIfNeeded(targetUserID: targetAccountUserID, accountUserID: account)
            }
        } catch {
            assertionFailure("Failed to bootstrap filesystem: \(error)")
        }
    }

    func registerWithEmail(email: String, password: String) async throws {
        let auth = try await BackendAPIClient.shared.emailRegister(email: email, password: password)
        applyAuth(auth)
    }

    func loginWithEmail(email: String, password: String) async throws {
        let auth = try await BackendAPIClient.shared.emailLogin(email: email, password: password)
        applyAuth(auth)
    }

    func loginWithOAuth(provider: String, idToken: String) async throws {
        let auth = try await BackendAPIClient.shared.oauthLogin(provider: provider, idToken: idToken)
        applyAuth(auth)
    }

    func applyAuth(_ auth: BackendAuthResponse) {
        let fromGuest = !isLoggedIn
        let previousGuestUserID = currentGuestScopedUserID
        let targetAccountUserID = "account_\(auth.userId)"

        if fromGuest {
            do {
                _ = try GuestDataRecoveryService.recover(
                    from: previousGuestUserID,
                    to: targetAccountUserID
                )
            } catch {
                print("⚠️ guest -> account local archive failed: \(error)")
            }
        }

        session = .account(
            userID: auth.userId,
            provider: auth.provider,
            email: auth.email,
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken,
            guestID: guestID
        )
        persistSession()

        if fromGuest {
            pendingMigrationFromGuestUserID = previousGuestUserID
            UserDefaults.standard.set(previousGuestUserID, forKey: Self.pendingGuestMigrationKey)
            bindGuestToAccount(guestID: guestID, accountUserID: auth.userId)
        }
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

    func logoutToGuest() {
        session = .guest(guestID: guestID)
        persistSession()
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
        if let account = accountUserID, !account.isEmpty {
            clearAutoRecoveryMarkers(for: "account_\(account)")
        }

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

    private func autoRecoverGuestSourcesIfNeeded(targetUserID: String, accountUserID: String?) {
        let candidates = GuestDataRecoveryService.discoverCandidates(currentUserID: targetUserID)
        guard !candidates.isEmpty else { return }

        var recoveredByTarget = loadAutoRecoveredGuestSources()
        var recoveredSources = Set(recoveredByTarget[targetUserID] ?? [])
        var changed = false

        for candidate in candidates {
            let sourceUserID = candidate.userID
            if recoveredSources.contains(sourceUserID) { continue }
            do {
                _ = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)
                recoveredSources.insert(sourceUserID)
                changed = true
                if let accountUserID,
                   let sourceGuestID = guestID(fromGuestScopedUserID: sourceUserID) {
                    bindGuestToAccount(guestID: sourceGuestID, accountUserID: accountUserID)
                }
            } catch {
                print("⚠️ auto recover \(sourceUserID) -> \(targetUserID) failed: \(error)")
            }
        }

        guard changed else { return }
        recoveredByTarget[targetUserID] = Array(recoveredSources).sorted()
        saveAutoRecoveredGuestSources(recoveredByTarget)
    }

    private func guestID(fromGuestScopedUserID userID: String) -> String? {
        guard userID.hasPrefix("guest_") else { return nil }
        let id = String(userID.dropFirst("guest_".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
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
}
