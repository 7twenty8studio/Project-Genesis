import SwiftUI

/// Opens a church sermon by its link's slug: the outline, or why it can't
/// be shown (for members only, no longer available, hidden by the person,
/// or the feature switched off), asked again each time it opens so an
/// unpublish or a removal from the church applies at once.
struct ChurchSermonScreen: View {
    let initialSlug: String

    @Environment(\.churchSermons) private var backend
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(HiddenChurches.self) private var hidden
    @Environment(AuthService.self) private var auth
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var slug: String
    @State private var state: LoadState = .loading
    @State private var showsAccount = false

    enum LoadState: Equatable {
        case loading
        case loaded(ChurchSermonLookup)
        case failed(String)
    }

    init(slug: String) {
        initialSlug = slug
        _slug = State(initialValue: slug)
    }

    var body: some View {
        Group {
            if !FeaturePreferences.isAvailable(.churchSermons, flags: flags) {
                message(
                    systemImage: "text.book.closed",
                    title: String(localized: "Church sermons aren't available yet"),
                    detail: String(localized: "This part of Versely isn't open yet. Please try again later.")
                )
            } else if !features.isOn(.churchSermons) {
                FeatureOffView(feature: .churchSermons)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreen()
        .task(id: LoadKey(slug: slug, user: auth.user?.id)) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
    }

    private struct LoadKey: Hashable {
        let slug: String
        let user: UUID?
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
        case let .failed(text):
            VStack(spacing: 16) {
                message(systemImage: "wifi.exclamationmark", title: String(localized: "This sermon couldn't load"), detail: text)
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.bordered)
            }
        case .loaded(.notFound):
            message(
                systemImage: "text.book.closed",
                title: String(localized: "This sermon isn't available"),
                detail: String(localized: "The church may have unpublished it, or the link may be mistyped.")
            )
            .accessibilityIdentifier("churchSermon.notFound")
        case .loaded(.membersOnly):
            VStack(spacing: 16) {
                message(
                    systemImage: "person.2",
                    title: String(localized: "For church members"),
                    detail: auth.isSignedIn
                        ? String(localized: "This sermon is for members of its church. Join the church's group in Together with its invite code to read it.")
                        : String(localized: "This sermon is for members of its church. Sign in with the account you use in its group.")
                )
                if !auth.isSignedIn {
                    Button("Sign In") { showsAccount = true }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
            .accessibilityIdentifier("churchSermon.membersOnly")
        case let .loaded(.sermon(sermon)):
            if hidden.isHidden(sermon.groupID) {
                VStack(spacing: 16) {
                    message(
                        systemImage: "hand.raised",
                        title: String(localized: "You've hidden sermons from \(sermon.church)"),
                        detail: String(localized: "Show them again to read this one.")
                    )
                    Button("Show Sermons from \(sermon.church)") { hidden.set(sermon.groupID, hidden: false) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("churchSermon.showAgain")
                }
            } else {
                PublishedSermonView(sermon: sermon, onOpenSermon: { slug = $0 }, onHidden: {})
                    .id(sermon.slug)
            }
        }
    }

    private func message(systemImage: String, title: String, detail: String) -> some View {
        QuietEmptyState(systemImage: systemImage, title: title, message: detail)
            .padding(24)
    }

    private func load() async {
        guard FeaturePreferences.isAvailable(.churchSermons, flags: flags), features.isOn(.churchSermons) else { return }
        if case let .loaded(.sermon(shown)) = state, shown.slug != slug { state = .loading }
        do {
            state = .loaded(try await backend.sermon(slug: slug))
        } catch is CancellationError {
            return
        } catch {
            // Keep a sermon already on screen when a refresh fails offline.
            if case .loaded(.sermon) = state { return }
            state = .failed(CommunityError.from(error).errorDescription ?? "")
        }
    }
}
