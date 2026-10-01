import Combine
import SwiftUI

/// Chooses onboarding or the main app, and applies the paper theme everywhere.
struct RootView: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(BibleLibrary.self) private var library
    @Environment(ReadingProgress.self) private var progress
    @Environment(AppRouter.self) private var router
    @Environment(SyncService.self) private var sync
    @Environment(EntitlementService.self) private var entitlements
    @Environment(FeatureFlagService.self) private var flags
    @Environment(WhatsNewService.self) private var whatsNew
    @Environment(AudioPlayerService.self) private var audio
    @Environment(FeaturePreferences.self) private var features
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
                OnboardingView {
                    // A new install: what shipped with the app isn't news.
                    whatsNew.markShippedFeaturesSeen()
                    onboardingComplete = true
                }
            }
        }
        .whatsNewSheet(isReady: onboardingComplete && scenePhase == .active)
        .environment(\.palette, theme.palette)
        .tint(theme.palette.accent)
        // Explicit themes pin light or dark chrome; Auto follows the system.
        .preferredColorScheme(settings.preferences.theme == .automatic ? nil : (theme.isDark ? .dark : .light))
        .onOpenURL { url in
            if !onboardingComplete {
                whatsNew.markShippedFeaturesSeen()
                if !features.hasChosen { features.choose(OptionalFeature.defaults) }
            }
            onboardingComplete = true
            router.handle(url)
        }
        .task {
            entitlements.start()
            sync.start()
            Task { await flags.refresh() }
            Task { await audio.catalog.refresh() }
            Task { await PushNotifications.shared.refreshRegistration() }
            Task { await library.refreshCatalog() }
            refreshWidgets()
        }
        .onChange(of: entitlements.isPremium) { _, isPremium in
            if isPremium { sync.schedule(after: .zero) }
            keepThemeAvailable()
        }
        .onChange(of: entitlements.hasLoaded) { keepThemeAvailable() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.schedule(after: .zero)
                Task { await flags.refresh() }
                refreshWidgets()
            case .background:
                refreshWidgets()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .genesisUserDataDidChange)) { _ in refreshWidgets() }
        .onReceive(NotificationCenter.default.publisher(for: .genesisDidSync)) { _ in refreshWidgets() }
        .onChange(of: library.editionVersion) { router.reader.translationEditionChanged() }
        .onChange(of: library.currentTranslation) {
            refreshWidgets()
            // Keep listening in the new translation.
            audio.settingsChanged()
        }
    }

    /// If Premium has ended, a premium theme falls back to Auto.
    private func keepThemeAvailable() {
        guard entitlements.hasLoaded, !entitlements.allows(settings.preferences.theme) else { return }
        settings.preferences.theme = .automatic
    }

    private func refreshWidgets() {
        WidgetSnapshotWriter.refresh(library: library, progress: progress, context: modelContext)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(FeatureFlagService.self) private var flags
    @Environment(FeaturePreferences.self) private var features
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPhone tab bars fit five tabs before iOS adds "More". Like the Bible
    /// app, Search moves to a button (Home, Library) on compact widths so
    /// Home, Read, Library, Explore and Together always fit.
    private var searchIsTab: Bool { horizontalSizeClass == .regular }

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
            if features.isOn(.explore) {
                Tab("Explore", systemImage: "map", value: AppTab.explore) {
                    ExploreView()
                }
            }
            if features.shows(.together, flags: flags) {
                Tab("Together", systemImage: "person.3", value: AppTab.together) {
                    TogetherView()
                }
            }
            if searchIsTab {
                Tab(value: AppTab.search, role: .search) {
                    SearchView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.searchIsTab, searchIsTab)
        .sheet(isPresented: $router.showsSearch) {
            SearchSheet()
        }
        .onChange(of: router.tab) { keepTabAvailable() }
        .onChange(of: features.enabled) { keepTabAvailable() }
        .onChange(of: searchIsTab) { keepTabAvailable() }
        .task {
            // iPadOS can restore a previously selected tab after launch; a UI
            // test that asked to start in the reader must land there.
            if UITestingOptions.current.startVerse != nil { router.tab = .read }
        }
    }

    /// A hidden feature's tab (from a link or notification) falls back to Home.
    private func keepTabAvailable() {
        switch router.tab {
        case .explore where !features.isOn(.explore):
            router.tab = .home
        case .together where !features.shows(.together, flags: flags):
            router.tab = .home
        case .search where !searchIsTab:
            // Folding a Duo: carry on searching in the sheet.
            router.tab = .home
            router.showsSearch = true
        default:
            break
        }
    }
}
