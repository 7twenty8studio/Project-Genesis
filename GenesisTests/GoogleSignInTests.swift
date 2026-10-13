import Foundation
import Testing
@testable import Genesis

struct GoogleSignInTests {
    private let baseURL = URL(string: "https://example.supabase.co")!

    // MARK: PKCE

    @Test func verifierHasAnAllowedLengthAndCharacters() {
        let verifier = OAuthPKCE.verifier()
        let allowed = Set(OAuthPKCE.verifierCharacters)
        let onlyAllowed = verifier.allSatisfy { allowed.contains($0) }
        #expect((43...128).contains(verifier.count))
        #expect(onlyAllowed)

        let short = OAuthPKCE.verifier(length: 10)
        let long = OAuthPKCE.verifier(length: 500)
        #expect(short.count == 43)
        #expect(long.count == 128)

        let another = OAuthPKCE.verifier()
        #expect(verifier != another)
    }

    @Test func challengeIsBase64URLOfTheSHA256() {
        // Expected value computed independently:
        // printf '%s' <verifier> | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
        let challenge = OAuthPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r7wW1gFWFOEjXk")
        #expect(challenge == "bwWFMyPfdG9qreDhH2lmftFx_dFeLDalzcT1gb_j68g")
        let urlSafe = !challenge.contains("+") && !challenge.contains("/") && !challenge.contains("=")
        #expect(urlSafe)
        #expect(challenge.count == 43)
    }

    // MARK: Authorize URL

    @Test func authorizeURLAsksSupabaseForGoogleWithTheChallenge() throws {
        let url = try #require(GoogleOAuth.authorizeURL(baseURL: baseURL, challenge: "abc-_123"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        #expect(components.host == "example.supabase.co")
        #expect(components.path == "/auth/v1/authorize")
        #expect(query["provider"] == "google")
        #expect(query["redirect_to"] == "versely://auth-callback")
        #expect(query["code_challenge"] == "abc-_123")
        #expect(query["code_challenge_method"] == "s256")
    }

    // MARK: Callback

    @Test func callbackWithACode() throws {
        let url = try #require(URL(string: "versely://auth-callback?code=98f1c0de-1234"))
        #expect(GoogleOAuth.isCallback(url))
        #expect(GoogleOAuth.parse(url) == .code("98f1c0de-1234"))
    }

    @Test func callbackWithAnError() throws {
        let query = try #require(URL(string: "versely://auth-callback?error=access_denied&error_description=Unable+to+exchange+external+code"))
        #expect(GoogleOAuth.parse(query) == .error("Unable to exchange external code"))

        let fragment = try #require(URL(string: "versely://auth-callback#error=server_error&error_description=Database%20error"))
        #expect(GoogleOAuth.parse(fragment) == .error("Database error"))

        let bare = try #require(URL(string: "versely://auth-callback?error=access_denied"))
        #expect(GoogleOAuth.parse(bare) == .error(nil))
    }

    @Test func callbackWithoutACodeIsInvalid() throws {
        let empty = try #require(URL(string: "versely://auth-callback"))
        let blankCode = try #require(URL(string: "versely://auth-callback?code="))
        let otherLink = try #require(URL(string: "versely://plans?code=abc"))
        #expect(GoogleOAuth.parse(empty) == .invalid)
        #expect(GoogleOAuth.parse(blankCode) == .invalid)
        #expect(GoogleOAuth.parse(otherLink) == .invalid)
        #expect(!GoogleOAuth.isCallback(otherLink))
    }

    // MARK: Token request

    @Test func tokenBodyCarriesTheCodeAndVerifier() {
        let body = GoogleOAuth.tokenBody(code: "the-code", verifier: "the-verifier")
        #expect(body == ["auth_code": "the-code", "code_verifier": "the-verifier"])
    }

    // MARK: Account

    @Test func knowsAGoogleAccount() {
        let id = UUID()
        let google = AuthUser(id: id, email: "a@gmail.com", providers: ["google"])
        let both = AuthUser(id: id, email: "a@gmail.com", providers: ["email", "google", "apple"])
        #expect(google.usesSignInWithGoogle)
        #expect(!google.usesSignInWithApple)
        #expect(both.usesSignInWithGoogle)
        #expect(both.usesSignInWithApple)
    }
}
