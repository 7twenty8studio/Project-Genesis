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
    @Environment(AuthService.self) private var auth
    @Environment(FeatureFlagService.self) private var flags
    @Environment(WhatsNewService.self) private var whatsNew
    @Environment(AudioPlayerService.self) private var audio
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(FeaturePreferences.self) private var features
    @Environment(MorningWelcome.self) private var welcome
    @Environment(ChallengeAutoTick.self) private var challengeAutoTick
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsWelcome = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.complete") private var onboardingComplete = false

    var body: some View {
        // Night reading may swap the person's theme for Night or Starlight.
        let current = settings.currentTheme(premium: entitlements.allows(.premiumThemes))
        let theme = current.resolved(for: colorScheme)
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingView {
                    // A new install: what shipped with the app isn't news,
                    // and setup was today's welcome.
                    whatsNew.markShippedFeaturesSeen()
                    welcome.markShown()
                    onboardingComplete = true
                }
            }
        }
        .whatsNewSheet(isReady: onboardingComplete && scenePhase == .active && !showsWelcome)
        // Premium: a quiet welcome the first time Genesis opens each day.
        .fullScreenCover(isPresented: $showsWelcome) {
            MorningWelcomeView { showsWelcome = false }
        }
        // With the Seasons icon, move the Home Screen icon on with the season.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AppIcon.apply() }
        }
        .environment(\.palette, theme.palette)
        .tint(theme.palette.accent)
        // Explicit themes pin light or dark chrome; Auto follows the system.
        .preferredColorScheme(current == .automatic ? nil : (theme.isDark ? .dark : .light))
        // Switch to and from the night theme on time.
        .task(id: settings.preferences.nightReading) { await followNightReading() }
        .onOpenURL { url in
            if !onboardingComplete {
                whatsNew.markShippedFeaturesSeen()
                if !features.hasChosen { features.choose(OptionalFeature.defaults) }
            }
            onboardingComplete = true
            // Opened from a link or widget: go there, not to the welcome.
            welcome.markShown()
            showsWelcome = false
            router.handle(url)
        }
        .task {
            entitlements.start()
            sync.start()
            Task { await flags.refresh() }
            Task { await audio.catalog.refresh() }
            Task { await PushNotifications.shared.refreshRegistration() }
            Task { await library.refreshCatalog() }
            Task { await challengeAutoTick.refresh() }
            refreshWidgets()
            offerWelcome()
        }
        .onChange(of: entitlements.isPremium) {
            keepThemeAvailable()
            keepAmbientAvailable()
            refreshWidgets()
        }
        .onChange(of: auth.user?.id) {
            Task { await refreshGrant() }
            Task { await challengeAutoTick.refresh(force: true) }
        }
        .onChange(of: entitlements.hasLoaded) {
            keepThemeAvailable()
            keepAmbientAvailable()
            offerWelcome()
        }
        // Ambient sounds sit quieter while the Bible is read aloud.
        .onChange(of: audio.isPlaying) { _, playing in ambient.setDucked(playing) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                settings.nightClock = .now
                sync.schedule(after: .zero)
                Task { await refreshGrant() }
                audio.liveActivity.appBecameActive()
                Task { await flags.refresh() }
                Task { await challengeAutoTick.refresh() }
                refreshWidgets()
                offerWelcome()
            case .background:
                refreshWidgets()
                // A welcome that couldn't be shown (another sheet was up) is
                // offered again next time, and What's New isn't held back.
                showsWelcome = false
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .genesisUserDataDidChange)) { _ in refreshWidgets() }
        .onReceive(NotificationCenter.default.publisher(for: .genesisDidSync)) { _ in refreshWidgets() }
        .onChange(of: library.editionVersion) { router.reader.translationEditionChanged() }
        // Premium widgets follow the reading theme.
        .onChange(of: settings.preferences.theme) { refreshWidgets() }
        .onChange(of: library.currentTranslation) {
            refreshWidgets()
            // Keep listening in the new translation.
            audio.settingsChanged()
        }
    }

    /// The morning welcome, once a day, once Premium is known and the app is
    /// in front. The view marks the day as greeted when it actually appears.
    private func offerWelcome() {
        guard onboardingComplete, scenePhase == .active, entitlements.hasLoaded, !showsWelcome,
              welcome.shouldShow(isPremium: entitlements.isPremium) else { return }
        showsWelcome = true
    }

    /// If Premium has ended, a premium theme falls back to Auto.
    private func keepThemeAvailable() {
        guard entitlements.hasLoaded, !entitlements.allows(settings.preferences.theme) else { return }
        settings.preferences.theme = .automatic
    }

    /// Moves the night-reading clock on at each edge of the night window
    /// (8 pm and 6 am by default), so the theme changes on time without
    /// redrawing every minute.
    private func followNightReading() async {
        while !Task.isCancelled {
            settings.nightClock = .now
            guard let next = NightReading.nextChange(after: .now, schedule: settings.preferences.nightReading, calendar: .current) else { return }
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 1)))
        }
    }

    /// Premium given by the owner (public.premium_grants) for this account.
    private func refreshGrant() async {
        guard auth.isSignedIn else {
            await entitlements.refreshGrant(client: auth.client, accessToken: nil)
            return
        }
        // Offline (the token can't refresh): keep what we knew.
        guard let token = try? await auth.accessToken() else { return }
        await entitlements.refreshGrant(client: auth.client, accessToken: token)
    }

    /// Ambient sounds are Premium: stop them if Premium has ended.
    private func keepAmbientAvailable() {
        guard entitlements.hasLoaded, !entitlements.allows(.ambientSounds), ambient.showsControls else { return }
        ambient.close()
    }

    private func refreshWidgets() {
        WidgetSnapshotWriter.applyPendingPlanDays(context: modelContext)
        WidgetSnapshotWriter.refresh(library: library, progress: progress, context: modelContext, isPremium: entitlements.isPremium, theme: settings.preferences.theme)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AudioPlayerService.self) private var audio
    @Environment(AmbientSoundService.self) private var ambient
    @State private var showsNowPlaying = false
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
        // What's playing, on every tab but the reader (which has its own bar).
        .modifier(NowPlayingAccessoryModifier(isEnabled: showsPlayer, onOpen: { showsNowPlaying = true }))
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingSheet()
                .presentationDetents([.medium, .large])
        }
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

    private var showsPlayer: Bool {
        router.tab != .read && ((audio.isActive && features.isOn(.listen)) || ambient.showsControls)
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
