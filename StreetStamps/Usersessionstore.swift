import Foundation
import SwiftUI

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
            let paths = StoragePath(userID: currentUserID)
            try paths.ensureBaseDirectoriesExist()
            try DataMigrator.migrateLegacyIfNeeded(paths: paths)
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
        let previousGuestUserID = currentUserID

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
        }
    }

    func logoutToGuest() {
        session = .guest(guestID: guestID)
        persistSession()
    }

    func clearPendingGuestMigrationMarker() {
        pendingMigrationFromGuestUserID = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingGuestMigrationKey)
    }

    private func persistSession() {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionDataKey)
        }
    }

    private static func loadOrCreateGuestID() -> String {
        if let existing = UserDefaults.standard.string(forKey: guestIDKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: guestIDKey)
        return id
    }
}
