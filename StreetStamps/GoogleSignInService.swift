import Foundation
import GoogleSignIn
import UIKit
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

enum GoogleSignInService {
    static func signIn(presentingViewController: UIViewController? = nil) async throws -> FirebaseAuthenticatedSession {
        if let issue = BackendConfig.firebaseSetupIssue() {
            throw BackendAPIError.server(issue)
        }
        let clientID = BackendConfig.googleIOSClientID
        if !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        let presenter = presentingViewController ?? topViewController()
        guard let presenter else {
            throw BackendAPIError.server("无法获取当前页面用于 Google 登录")
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
            throw BackendAPIError.server("Google 登录未返回 idToken")
        }
        #if canImport(FirebaseAuth)
        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let authResult = try await Auth.auth().signIn(with: credential)
        return try await makeFirebaseAuthenticatedSession(for: authResult.user, forceRefresh: true)
        #else
        throw BackendAPIError.server("FirebaseAuth 未接入当前 target。")
        #endif
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
