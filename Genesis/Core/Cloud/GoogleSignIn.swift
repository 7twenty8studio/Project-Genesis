import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// PKCE (RFC 7636) for signing in through a browser: a random verifier stays
/// on the device, the server gets only its SHA-256 challenge, and the one-time
/// code from the callback is worthless without the verifier.
enum OAuthPKCE {
    /// RFC 7636's unreserved characters.
    static let verifierCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A random verifier; RFC 7636 allows 43–128 characters.
    static func verifier(length: Int = 64) -> String {
        let length = min(max(length, 43), 128)
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            verifierCharacters[Int.random(in: 0..<verifierCharacters.count, using: &generator)]
        })
    }

    /// The S256 challenge: base64url (no padding) of the verifier's SHA-256.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Sign in with Google through Supabase's OAuth (PKCE) flow, with no Google
/// SDK: Supabase's /authorize page sends the person to Google, Google back to
/// Supabase, and Supabase to versely://auth-callback?code=…, which the app
/// swaps (with the verifier) for a session at /token?grant_type=pkce.
enum GoogleOAuth {
    static let provider = "google"
    static let callbackScheme = GenesisLink.scheme
    static let callbackHost = GenesisLink.authCallbackHost
    /// Must be in Supabase › Authentication › URL Configuration › Redirect URLs.
    static let redirectURL = "\(GenesisLink.scheme)://\(GenesisLink.authCallbackHost)"

    enum Callback: Equatable, Sendable {
        case code(String)
        /// The server or Google refused; the description when it sent one.
        case error(String?)
        /// Not our callback, or neither a code nor an error.
        case invalid
    }

    /// `<Supabase>/auth/v1/authorize?provider=google&redirect_to=…&code_challenge=…&code_challenge_method=s256`.
    static func authorizeURL(baseURL: URL, challenge: String) -> URL? {
        var components = URLComponents(url: baseURL.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components?.url
    }

    /// True for versely://auth-callback, which only the sign-in sheet handles.
    static func isCallback(_ url: URL) -> Bool {
        url.scheme == callbackScheme && url.host() == callbackHost
    }

    /// Reads the code (or the error) from the callback's query, or from its
    /// fragment, where Supabase puts some errors.
    static func parse(_ url: URL) -> Callback {
        guard isCallback(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .invalid }
        var items: [(String, String)] = (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        if let fragment = components.percentEncodedFragment {
            items += fragment.split(separator: "&").map { pair -> (String, String) in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts.first?.removingPercentEncoding ?? ""
                let decoded = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
                return (name, decoded)
            }
        }
        let found = items
        func value(_ name: String) -> String? {
            guard let match = found.first(where: { $0.0 == name })?.1, !match.isEmpty else { return nil }
            return match
        }
        if let code = value("code") { return .code(code) }
        if value("error") != nil || value("error_description") != nil {
            // Form encoding writes spaces as "+".
            return .error(value("error_description")?.replacingOccurrences(of: "+", with: " "))
        }
        return .invalid
    }

    /// The /token?grant_type=pkce body.
    static func tokenBody(code: String, verifier: String) -> [String: String] {
        ["auth_code": code, "code_verifier": verifier]
    }
}

/// Shows Supabase's Google sign-in page in an ASWebAuthenticationSession and
/// returns the callback's code.
///
/// `prefersEphemeralWebBrowserSession` is false: the sheet shares Safari's
/// cookies, so someone already signed in to Google in Safari just picks their
/// account instead of typing a password (and two-factor) again. The cost is
/// iOS's one-line "Versely wants to use … to sign in" prompt first; an
/// ephemeral session would skip it but make everyone sign in to Google afresh.
@MainActor
final class GoogleWebSignIn: NSObject {
    enum Outcome: Equatable, Sendable {
        case code(String)
        case cancelled
        case failed(String?)
    }

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var session: ASWebAuthenticationSession?
    /// The window the sheet appears over, found before it starts.
    private var anchor: ASPresentationAnchor?

    func code(from authorizeURL: URL) async -> Outcome {
        guard continuation == nil else { return .cancelled }
        guard let window = PresentationWindow.current() else { return .failed(nil) }
        anchor = window
        let session = ASWebAuthenticationSession(
            url: authorizeURL,
            callback: .customScheme(GoogleOAuth.callbackScheme)
        ) { @Sendable callbackURL, error in
            // Called once; finish() then lets go of the session (and this closure).
            let outcome = Self.outcome(callbackURL: callbackURL, error: error)
            Task { @MainActor in self.finish(outcome) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if !session.start() { finish(.failed(nil)) }
        }
    }

    nonisolated private static func outcome(callbackURL: URL?, error: (any Error)?) -> Outcome {
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return .cancelled }
            return .failed(nil)
        }
        guard let callbackURL else { return .failed(nil) }
        switch GoogleOAuth.parse(callbackURL) {
        case let .code(code): return .code(code)
        case let .error(description): return .failed(description)
        case .invalid: return .failed(nil)
        }
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
        session = nil
        anchor = nil
    }
}

extension GoogleWebSignIn: @preconcurrency ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Set in code(from:) before the session starts.
        anchor ?? PresentationWindow.current()!
    }
}
