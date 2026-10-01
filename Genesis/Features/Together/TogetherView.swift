import SwiftUI

/// The Together tab: your church groups, the prayer wall and reflections.
/// Everything here needs an account and a display name.
struct TogetherView: View {
    enum Area: String, CaseIterable, Identifiable {
        case groups, prayer, reflections
        var id: String { rawValue }
        var title: String {
            switch self {
            case .groups: "Groups"
            case .prayer: "Prayer Wall"
            case .reflections: "Reflections"
            }
        }
    }

    @Environment(AppRouter.self) private var router
    @Environment(CommunityStore.self) private var community
    @Environment(FeatureFlagService.self) private var flags
    @Environment(AuthService.self) private var auth
    @Environment(\.palette) private var palette
    @State private var section: Area = .groups
    @State private var showsAccount = false

    private var sections: [Area] {
        Area.allCases.filter { section in
            section == .groups ? flags.isOn(.groups) : flags.isOn(.community)
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.togetherPath) {
            content
                .themedScreen()
                .navigationTitle("Together")
                .toolbarTitleDisplayMode(.inlineLarge)
                .navigationDestination(for: TogetherRoute.self) { route in
                    switch route {
                    case let .group(id): GroupDetailView(groupID: id)
                    case let .post(post): CommunityPostDetailView(post: post)
                    }
                }
        }
        .task(id: auth.user?.id) { await community.refresh() }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .onChange(of: sections) {
            if !sections.contains(section), let first = sections.first { section = first }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !community.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !community.isSignedIn {
            signInPrompt
        } else if community.needsDisplayName {
            DisplayNameView()
        } else {
            VStack(spacing: 0) {
                if sections.count > 1 {
                    Picker("Show", selection: $section) {
                        ForEach(sections) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("together.section")
                }
                switch sections.contains(section) ? section : (sections.first ?? .groups) {
                case .groups: GroupsListView()
                case .prayer: CommunityFeedView(kind: .prayer)
                case .reflections: CommunityFeedView(kind: .reflection)
                }
            }
        }
    }

    private var signInPrompt: some View {
        ScrollView {
            VStack(spacing: 18) {
                QuietEmptyState(
                    systemImage: "person.3",
                    title: "Read and pray together",
                    message: "Join your church's group to follow a reading plan together, share prayer requests and talk about the day's passage. Sign in to get started; it's free."
                )
                Button {
                    showsAccount = true
                } label: {
                    Text("Sign In or Create Account")
                        .font(.headline)
                        .frame(maxWidth: 320, minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("together.signIn")
            }
            .padding(24)
        }
    }
}

/// Choose the name others see in groups and the community.
struct DisplayNameView: View {
    var onDone: (() -> Void)?

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should people call you?")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Your name is shown with your prayer requests and messages. Your first name, or how your church knows you, works well.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Display name", text: $name)
                    .textContentType(.givenName)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier("together.displayName")
            } footer: {
                if let error = community.errorMessage {
                    Text(error).foregroundStyle(.orange)
                }
            }
            Section {
                Button(action: save) {
                    if isSaving { ProgressView() } else { Text("Continue") }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .accessibilityIdentifier("together.saveName")
            }
        }
        .onAppear {
            name = community.profile?.displayName ?? ""
            focused = true
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if await community.setDisplayName(name) { onDone?() }
            isSaving = false
        }
    }
}

/// The community guidelines, accepted once before posting publicly (App Store
/// guideline 1.2 asks for terms that rule out objectionable content).
struct CommunityGuidelinesView: View {
    let onAccepted: () -> Void

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    static let rules: [(String, String)] = [
        ("heart", "Be kind. Encourage one another and disagree gently."),
        ("hand.raised", "No abuse, harassment, hate, sexual content or threats. There's no tolerance for objectionable content or abusive users."),
        ("lock", "Keep others' private details private. Don't share anyone's prayer request outside Genesis."),
        ("megaphone", "No advertising, spam or fundraising."),
        ("flag", "Report anything that breaks these rules. Reported posts are reviewed, and people who break them are removed."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Before you post, please agree to keep the community a safe, encouraging place for everyone.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                    ForEach(Self.rules, id: \.1) { rule in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: rule.0)
                                .foregroundStyle(palette.accent)
                                .frame(width: 26)
                            Text(rule.1)
                                .foregroundStyle(palette.text)
                        }
                    }
                    Text("Posts are public to everyone signed in to Genesis. You can block anyone, and report any post or comment.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    if let error = community.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isSaving = true
                    Task {
                        if await community.acceptCommunityTerms() {
                            dismiss()
                            onAccepted()
                        }
                        isSaving = false
                    }
                } label: {
                    Text("I Agree")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityIdentifier("community.acceptGuidelines")
            }
            .themedScreen()
            .navigationTitle("Community Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
