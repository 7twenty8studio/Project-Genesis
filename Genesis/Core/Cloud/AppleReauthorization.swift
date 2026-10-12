import AuthenticationServices
import UIKit

/// Asks the person to confirm with Sign in with Apple (no scopes, so no name
/// or email is shared again) and returns Apple's fresh authorization code.
/// Deleting an Apple account sends it to the delete-account function, which
/// exchanges it for a token and revokes it; nothing is kept on the device.
@MainActor
final class AppleReauthorization: NSObject {
    enum Outcome: Equatable {
        case code(String)
        case cancelled
        case failed(String)
    }

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var controller: ASAuthorizationController?
    /// The window the Apple sheet appears over, found before it's requested.
    private var anchor: ASPresentationAnchor?

    func authorizationCode() async -> Outcome {
        guard continuation == nil else { return .cancelled }
        guard let window = Self.currentWindow() else {
            return .failed(String(localized: "Apple didn't confirm your account. Your account wasn't deleted."))
        }
        anchor = window
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
        controller = nil
        anchor = nil
    }

    /// The key window of the active scene (or any window), so the sheet has
    /// somewhere to appear; nil only if the app has no window at all.
    private static func currentWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.keyWindow ?? scene?.windows.first { return window }
        if let scene { return UIWindow(windowScene: scene) }
        return nil
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8) else {
            finish(.failed(String(localized: "Apple didn't confirm your account. Your account wasn't deleted.")))
            return
        }
        finish(.code(code))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(.cancelled)
        } else {
            finish(.failed(String(localized: "Apple didn't confirm your account. Your account wasn't deleted.")))
        }
    }
}

extension AppleReauthorization: @preconcurrency ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Set in authorizationCode() before the request is performed.
        anchor ?? Self.currentWindow()!
    }
}
