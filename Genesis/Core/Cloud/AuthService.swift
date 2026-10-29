import Foundation
import Observation

/// Who is signed in. Without an account the app works fully offline as a
/// guest; signing in adds free cloud backup and sync across devices.
@MainActor
@Observable
final class AuthService {
    private(set) var user: AuthUser?
    private(set) var isWorking = false
    var errorMessage: String?
    var infoMessage: String?

    /// False when the build has no Supabase configuration.
    var isAvailable: Bool { client != nil }
    var isSignedIn: Bool { user != nil }

    @ObservationIgnored let client: SupabaseClient?
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private var session: AuthSession?
    @ObservationIgnored private var refreshTask: Task<AuthSession, Error>?
    /// `refreshNameIfMissing` asks once per launch.
    @ObservationIgnored private var checkedName = false
    @ObservationIgnored var onSignIn: (@MainActor (AuthUser) -> Void)?
    /// Runs while still signed in, e.g. to stop this device's notifications.
    @ObservationIgnored var beforeSignOut: (@MainActor () async -> Void)?

    private static let sessionAccount = "session"

    init(client: SupabaseClient?, keychain: KeychainStore = KeychainStore(), restoresSession: Bool = true) {
        self.client = client
        self.keychain = keychain
        if restoresSession, client != nil, let saved = keychain.load(AuthSession.self, account: Self.sessionAccount) {
            session = saved
            user = saved.user
        }
    }

    // MARK: Sign in

    func signIn(email: String, password: String) async {
        let email = Self.clean(email)
        await run { client in try await client.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        let email = Self.clean(email)
        await run { client in try await client.signUp(email: email, password: password) }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        await run { client in try await client.signInWithApple(idToken: idToken, nonce: nonce) }
    }

    /// Sign in with Google: Supabase's Google page in a web sheet, then the
    /// returned code and this sign-in's PKCE verifier swapped for a session.
    /// Closing the sheet is silent.
    func signInWithGoogle() async {
        guard let client else {
            errorMessage = SupabaseError.notConfigured.localizedDescription
            return
        }
        guard !isWorking else { return }
        let verifier = OAuthPKCE.verifier()
        guard let url = GoogleOAuth.authorizeURL(baseURL: client.baseURL, challenge: OAuthPKCE.challenge(for: verifier)) else {
            errorMessage = String(localized: "Sign in with Google didn't work. Please try again.")
            return
        }
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        let outcome = await GoogleWebSignIn().code(from: url)
        isWorking = false
        switch outcome {
        case let .code(code):
            await run { client in try await client.signIn(oauthCode: code, verifier: verifier) }
        case .cancelled:
            return
        case let .failed(description):
            if let description {
                errorMessage = String(localized: "Sign in with Google didn't work: \(description)")
            } else {
                errorMessage = String(localized: "Sign in with Google didn't work. Please try again.")
            }
        }
    }

    func sendPasswordReset(email: String) async {
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.sendPasswordReset(email: Self.clean(email))
            infoMessage = String(localized: "If an account exists for that email, a reset link is on its way.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Changes the signed-in account's password. True when it worked.
    func changePassword(to newPassword: String) async -> Bool {
        guard let client else { return false }
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            let token = try await accessToken()
            try await client.updatePassword(newPassword, accessToken: token)
            infoMessage = String(localized: "Your password was changed.")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reads the account from the server once when the saved session has no
    /// name yet (signed in before the name was kept), for Home's greeting.
    /// Quiet: a failure leaves things as they are.
    func refreshNameIfMissing() async {
        guard let client, let session, session.user.name == nil, !checkedName else { return }
        checkedName = true
        guard let token = try? await accessToken(),
              let current = try? await client.currentUser(accessToken: token),
              let latest = self.session, latest.user != current else { return }
        store(AuthSession(accessToken: latest.accessToken, refreshToken: latest.refreshToken, expiresAt: latest.expiresAt, user: current))
    }

    /// Whether the account signs in with Apple, asked of the server (so a
    /// linked identity counts), falling back to what was saved at sign-in.
    /// Nil (with `errorMessage` set) when it couldn't be checked.
    func usesSignInWithApple() async -> Bool? {
        guard let client else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let token = try await accessToken()
            let current = try await client.currentUser(accessToken: token)
            if let session, session.user != current {
                store(AuthSession(accessToken: session.accessToken, refreshToken: session.refreshToken, expiresAt: session.expiresAt, user: current))
            }
            return current.usesSignInWithApple
        } catch {
            if let user, user.providers != nil { return user.usesSignInWithApple }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private struct DeleteAccountBody: Encodable {
        let appleAuthorizationCode: String?
    }

    /// Deletes the account and everything stored with it on the server (the
    /// delete-account Edge Function), then signs out. True when it worked.
    /// For a Sign in with Apple account, `appleAuthorizationCode` is a fresh
    /// code from confirming with Apple, which the function uses to revoke
    /// Versely's Apple tokens (App Store guideline 5.1.1(v)).
    func deleteAccount(appleAuthorizationCode: String? = nil) async -> Bool {
        guard let client else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let token = try await accessToken()
            // Plain JSONEncoder: the function reads the camelCase key, and a nil code is left out.
            let body = try JSONEncoder().encode(DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode))
            let (_, status) = try await client.callFunction("delete-account", body: body, accessToken: token)
            guard (200..<300).contains(status) else {
                errorMessage = String(localized: "Your account couldn't be deleted. Please try again.")
                return false
            }
            await beforeSignOut?()
            session = nil
            user = nil
            keychain.delete(account: Self.sessionAccount)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        await beforeSignOut?()
        if let client, let session { await client.signOut(session) }
        session = nil
        user = nil
        keychain.delete(account: Self.sessionAccount)
    }

    /// A current access token, refreshed when close to expiry.
    func accessToken() async throws -> String {
        guard let client, let current = session else { throw SupabaseError.notConfigured }
        guard current.needsRefresh else { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await client.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            store(refreshed)
            return refreshed.accessToken
        } catch SupabaseError.http(let status, _) where status == 400 || status == 401 {
            // The refresh token was revoked: the person needs to sign in again.
            await signOut()
            throw SupabaseError.http(status: status, message: String(localized: "Your session has ended. Please sign in again."))
        }
    }

    // MARK: Helpers

    private func run(_ operation: @escaping @Sendable (SupabaseClient) async throws -> AuthSession) async {
        guard let client else {
            errorMessage = SupabaseError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do {
            let newSession = try await operation(client)
            store(newSession)
            onSignIn?(newSession.user)
        } catch SupabaseError.emailConfirmationRequired {
            infoMessage = SupabaseError.emailConfirmationRequired.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func store(_ newSession: AuthSession) {
        session = newSession
        user = newSession.user
        keychain.save(newSession, account: Self.sessionAccount)
    }

    nonisolated private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
