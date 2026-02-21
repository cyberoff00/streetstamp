import Foundation
import GoogleSignIn
import UIKit

enum GoogleSignInService {
    static func signIn(presentingViewController: UIViewController? = nil) async throws -> String {
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
        return idToken
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
