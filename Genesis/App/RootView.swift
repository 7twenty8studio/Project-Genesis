import Combine
import SwiftUI

/// Chooses onboarding or the main app, and applies the paper theme everywhere.
struct RootView: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(BibleLibrary.self) private var library
    @Environment(ReadingProgress.self) private var progress
    @Environment(AppRouter.self) private var router
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
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
        .onOpenURL { url in
            onboardingComplete = true
            router.handle(url)
        }
        .task {
            sync.start()
            refreshWidgets()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.schedule(after: .zero)
                refreshWidgets()
            case .background:
                refreshWidgets()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .genesisUserDataDidChange)) { _ in refreshWidgets() }
        .onReceive(NotificationCenter.default.publisher(for: .genesisDidSync)) { _ in refreshWidgets() }
        .onChange(of: library.currentTranslation) { refreshWidgets() }
    }

    private func refreshWidgets() {
        WidgetSnapshotWriter.refresh(library: library, progress: progress, context: modelContext)
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
