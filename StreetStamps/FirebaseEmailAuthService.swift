import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

enum FirebaseEmailAuthService {
    static func register(email: String, password: String) async throws -> FirebaseAuthenticatedSession {
        try ensureConfigured()
        #if canImport(FirebaseAuth)
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = result.user
        try await user.sendEmailVerification()
        return try await authenticatedSession(for: user, forceRefresh: true)
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    static func signIn(email: String, password: String) async throws -> FirebaseAuthenticatedSession {
        try ensureConfigured()
        #if canImport(FirebaseAuth)
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return try await authenticatedSession(for: result.user, forceRefresh: true)
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    static func sendPasswordReset(email: String) async throws {
        try ensureConfigured()
        #if canImport(FirebaseAuth)
        try await Auth.auth().sendPasswordReset(withEmail: email)
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    static func resendVerificationEmail() async throws {
        try ensureConfigured()
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw BackendAPIError.unauthorized
        }
        try await user.sendEmailVerification()
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    static func reloadCurrentUser() async throws -> FirebaseAuthenticatedSession? {
        try ensureConfigured()
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return nil }
        try await user.reload()
        guard let refreshedUser = Auth.auth().currentUser else { return nil }
        return try await authenticatedSession(for: refreshedUser, forceRefresh: true)
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    static func signOut() throws {
        #if canImport(FirebaseAuth)
        try Auth.auth().signOut()
        #endif
    }

    private static func ensureConfigured() throws {
        if let issue = BackendConfig.firebaseSetupIssue() {
            throw BackendAPIError.server(issue)
        }
    }

    #if canImport(FirebaseAuth)
    private static func authenticatedSession(
        for user: User,
        forceRefresh: Bool
    ) async throws -> FirebaseAuthenticatedSession {
        try await makeFirebaseAuthenticatedSession(for: user, forceRefresh: forceRefresh)
    }
    #endif
}
