import SwiftUI

/// Chooses onboarding or the main app, and applies the paper theme everywhere.
struct RootView: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("onboarding.complete") private var onboardingComplete = false

    var body: some View {
        let theme = settings.preferences.theme.resolved(for: colorScheme)
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingView { onboardingComplete = true }
            }
        }
        .environment(\.palette, theme.palette)
        .tint(theme.palette.accent)
        // Explicit themes pin light or dark chrome; Auto follows the system.
        .preferredColorScheme(settings.preferences.theme == .automatic ? nil : (theme.isDark ? .dark : .light))
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Read", systemImage: "book", value: AppTab.read) {
                ReaderView()
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            // iPadOS can restore a previously selected tab after launch; a UI
            // test that asked to start in the reader must land there.
            if UITestingOptions.current.startVerse != nil { router.tab = .read }
        }
    }
}
