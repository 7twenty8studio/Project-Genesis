import AuthenticationServices
import CryptoKit
import Foundation

/// Nonce handling for Sign in with Apple. Apple receives the SHA-256 hash of a
/// random nonce; Supabase receives the raw nonce and checks they match, which
/// stops a stolen identity token being replayed.
enum AppleSignInNonce {
    static func random(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension ASAuthorization {
    /// The Apple identity token as a string, if this authorization carries one.
    var appleIdentityToken: String? {
        guard let credential = credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
