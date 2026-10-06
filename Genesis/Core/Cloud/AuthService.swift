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

    /// Deletes the account and everything stored with it on the server (the
    /// delete-account Edge Function), then signs out. True when it worked.
    func deleteAccount() async -> Bool {
        guard let client else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let token = try await accessToken()
            let (_, status) = try await client.callFunction("delete-account", body: Data("{}".utf8), accessToken: token)
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
