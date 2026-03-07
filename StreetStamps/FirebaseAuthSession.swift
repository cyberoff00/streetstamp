import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct FirebaseAuthSessionSnapshot: Equatable {
    let uid: String
    let email: String?
    let emailVerified: Bool
    let providerID: String
}

struct FirebaseAuthenticatedSession: Equatable {
    let snapshot: FirebaseAuthSessionSnapshot
    let idToken: String
}

protocol FirebaseAuthSessionProviding: AnyObject {
    func currentUser() -> FirebaseAuthSessionSnapshot?
    func currentIDToken(forceRefresh: Bool) async throws -> String?
}

enum FirebaseAuthSession {
    private static var provider: FirebaseAuthSessionProviding = LiveFirebaseAuthSessionProvider()

    static var currentUser: FirebaseAuthSessionSnapshot? {
        provider.currentUser()
    }

    static func currentIDToken(forceRefresh: Bool = false) async throws -> String? {
        try await provider.currentIDToken(forceRefresh: forceRefresh)
    }

    static func installTestingProvider(_ provider: FirebaseAuthSessionProviding) {
        self.provider = provider
    }

    static func resetTestingProvider() {
        provider = LiveFirebaseAuthSessionProvider()
    }
}

private final class LiveFirebaseAuthSessionProvider: FirebaseAuthSessionProviding {
    func currentUser() -> FirebaseAuthSessionSnapshot? {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return nil }
        return FirebaseAuthSessionSnapshot(
            uid: user.uid,
            email: user.email,
            emailVerified: user.isEmailVerified,
            providerID: user.providerData.first?.providerID ?? ""
        )
        #else
        return nil
        #endif
    }

    func currentIDToken(forceRefresh: Bool) async throws -> String? {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDTokenResult(forcingRefresh: forceRefresh).token
        #else
        if let issue = BackendConfig.firebaseSetupIssue() {
            throw BackendAPIError.server(issue)
        }
        return nil
        #endif
    }
}

#if canImport(FirebaseAuth)
func makeFirebaseAuthenticatedSession(
    for user: User,
    forceRefresh: Bool
) async throws -> FirebaseAuthenticatedSession {
    let token = try await user.getIDTokenResult(forcingRefresh: forceRefresh).token
    let snapshot = FirebaseAuthSessionSnapshot(
        uid: user.uid,
        email: user.email,
        emailVerified: user.isEmailVerified,
        providerID: user.providerData.first?.providerID ?? ""
    )
    return FirebaseAuthenticatedSession(snapshot: snapshot, idToken: token)
}
#endif
