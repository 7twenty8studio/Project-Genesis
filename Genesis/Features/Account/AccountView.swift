import AuthenticationServices
import SwiftUI

/// Sign in, sign up or stay a guest; when signed in, sync status and sign out.
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.user {
                    SignedInView(user: user)
                } else {
                    SignInView()
                }
            }
            .themedScreen()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("account.done")
                }
            }
        }
    }
}

// MARK: - Signed out

private struct SignInView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, createAccount
        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign In" : "Create Account" }
    }

    @Environment(AuthService.self) private var auth
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !auth.isWorking
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep your notes safe")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Sign in to back up your highlights, notes, reading plans and prayers, and see them on all your devices. Everything also works without an account.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(Color.clear)
            }

            if !auth.isAvailable {
                Section {
                    Label("Cloud sync isn't set up in this build.", systemImage: "icloud.slash")
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Section {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = AppleSignInNonce.random()
                    appleNonce = nonce
                    request.requestedScopes = [.email]
                    request.nonce = AppleSignInNonce.sha256(nonce)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .listRowInsets(EdgeInsets())
                .disabled(!auth.isAvailable || auth.isWorking)
                .accessibilityIdentifier("account.apple")
            }

            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .accessibilityIdentifier("account.email")
                SecureField(mode == .signIn ? "Password" : "Password (6+ characters)", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .accessibilityIdentifier("account.password")

                Button(action: submit) {
                    HStack {
                        Spacer()
                        if auth.isWorking { ProgressView() } else { Text(mode.title).bold() }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || !auth.isAvailable)
                .accessibilityIdentifier("account.submit")

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task { await auth.sendPasswordReset(email: email) }
                    }
                    .font(.footnote)
                    .disabled(!email.contains("@"))
                }
            } footer: {
                if let message = auth.errorMessage {
                    Text(message).foregroundStyle(.red)
                } else if let message = auth.infoMessage {
                    Text(message)
                }
            }

            Section {
                Button("Continue as Guest") { dismiss() }
                    .accessibilityIdentifier("account.guest")
            } footer: {
                Text("As a guest, everything stays on this device. You can sign in any time and your notes will come with you.")
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { password = "" }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                await auth.signUp(email: email, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let token = authorization.appleIdentityToken else {
                auth.errorMessage = "Apple didn't return a sign-in token. Please try again."
                return
            }
            let nonce = appleNonce
            Task { await auth.signInWithApple(idToken: token, nonce: nonce) }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            auth.errorMessage = "Sign in with Apple isn't available yet: \(error.localizedDescription)"
        }
    }
}

// MARK: - Signed in

private struct SignedInView: View {
    let user: AuthUser

    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @State private var confirmSignOut = false
    @State private var premium: PremiumFeature?

    var body: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: user.email ?? "Apple ID")
                    .accessibilityIdentifier("account.signedInAs")
            }

            if !entitlements.allows(.cloudBackup) {
                Section {
                    Button {
                        premium = .cloudBackup
                    } label: {
                        Label("Back up with Premium", systemImage: "icloud")
                    }
                    .accessibilityIdentifier("account.backupPremium")
                } header: {
                    Text("Cloud Backup")
                } footer: {
                    Text("Your highlights, notes, plans and prayers are saved on this device. Cloud backup and sync across devices are part of Genesis Premium.")
                }
            } else {
            Section {
                HStack {
                    Label(statusText, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                    Spacer()
                    if sync.status == .syncing { ProgressView() }
                }
                Button("Sync Now") {
                    Task { await sync.syncNow() }
                }
                .disabled(sync.status == .syncing)
            } header: {
                Text("Cloud Sync")
            } footer: {
                Text("Highlights, notes, bookmarks, reading plans and prayers sync automatically. Prayers are private to your account.")
            }
            }

            Section {
                Button("Sign Out", role: .destructive) { confirmSignOut = true }
                    .accessibilityIdentifier("account.signOut")
            }
        }
        .premiumSheet($premium)
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out and Keep Data on This Device") { signOut(removeLocalData: false) }
            Button("Sign Out and Remove Data from This Device", role: .destructive) { signOut(removeLocalData: true) }
        } message: {
            Text("Your data stays safe in your account either way.")
        }
    }

    private var statusText: String {
        switch sync.status {
        case .syncing: "Syncing\u{2026}"
        case let .failed(message): message
        case .idle:
            if let last = sync.lastSyncedAt {
                "Synced \(last.formatted(.relative(presentation: .named)))"
            } else {
                "Waiting to sync"
            }
        }
    }

    private var statusSymbol: String {
        switch sync.status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.icloud"
        case .idle: "checkmark.icloud"
        }
    }

    private var statusColor: Color {
        if case .failed = sync.status { return .orange }
        return palette.text
    }

    private func signOut(removeLocalData: Bool) {
        Task {
            await auth.signOut()
            sync.accountDidSignOut(removeLocalData: removeLocalData)
        }
    }
}
