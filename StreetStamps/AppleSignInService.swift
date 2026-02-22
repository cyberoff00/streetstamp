import Foundation
import AuthenticationServices
import UIKit

@MainActor
enum AppleSignInService {
    static func signIn() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let req = ASAuthorizationAppleIDProvider().createRequest()
            req.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [req])
            let delegate = Delegate { result in
                switch result {
                case .success(let token): continuation.resume(returning: token)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            delegate.retainCycle = delegate
            controller.performRequests()
        }
    }

    private final class Delegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        enum Result {
            case success(String)
            case failure(Error)
        }

        var onResult: (Result) -> Void
        var retainCycle: Delegate?

        init(onResult: @escaping (Result) -> Void) {
            self.onResult = onResult
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let activeScenes = scenes.filter { $0.activationState == .foregroundActive }
            if let keyWindow = activeScenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let anyActiveWindow = activeScenes.flatMap(\.windows).first {
                return anyActiveWindow
            }
            if let fallbackWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.flatMap(\.windows).first {
                return fallbackWindow
            }
            return ASPresentationAnchor()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            defer { retainCycle = nil }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.isEmpty else {
                onResult(.failure(BackendAPIError.server("Apple 登录未返回 idToken")))
                return
            }
            onResult(.success(token))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            defer { retainCycle = nil }
            onResult(.failure(error))
        }
    }
}
