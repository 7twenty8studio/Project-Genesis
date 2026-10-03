import SwiftData
import SwiftUI

@main
struct GenesisApp: App {
    @UIApplicationDelegateAdaptor(GenesisAppDelegate.self) private var appDelegate
    @State private var library: BibleLibrary
    @State private var settings: ReaderSettings
    @State private var progress: ReadingProgress
    @State private var reader: ReaderViewModel
    @State private var router: AppRouter
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var entitlements: EntitlementService
    @State private var assistant: StudyAssistant
    @State private var flags: FeatureFlagService
    @State private var whatsNew: WhatsNewService
    @State private var audio: AudioPlayerService
    @State private var ambient: AmbientSoundService
    @State private var community: CommunityStore
    @State private var features: FeaturePreferences
    private let modelContainer: ModelContainer
    private let studyData = StudyRepository.bundled()
    private let topics = TopicRepository.bundled()

    init() {
        let testing = UITestingOptions.current
        if testing.isEnabled {
            testing.resetPersistentState()
        } else {
            CrashReporter.start()
        }

        // Read before anything changes it: someone who set up Genesis before
        // feature choices existed keeps everything they had.
        let features = FeaturePreferences(existingUser: UserDefaults.standard.bool(forKey: "onboarding.complete"))
        if testing.isSimple { features.choose([]) }
        _features = State(initialValue: features)

        let library = BibleLibrary()
        let progress = ReadingProgress()
        let settings = ReaderSettings()
        let reader = ReaderViewModel(library: library, progress: progress)
        let router = AppRouter(reader: reader)
        _library = State(initialValue: library)
        _settings = State(initialValue: settings)
        _progress = State(initialValue: progress)
        _reader = State(initialValue: reader)
        _router = State(initialValue: router)
        modelContainer = Self.makeModelContainer(inMemory: testing.isEnabled)
        // Available before the first page draws, so highlights show immediately.
        reader.modelContext = modelContainer.mainContext

        // UI tests never touch a real account.
        let auth = AuthService(client: testing.isEnabled ? nil : SupabaseClient.fromConfiguration(), restoresSession: !testing.isEnabled)
        let sync = SyncService(auth: auth, container: modelContainer)
        auth.onSignIn = { [weak sync] user in
            sync?.accountDidSignIn(user)
            Task { await PushNotifications.shared.upload() }
        }
        auth.beforeSignOut = { await PushNotifications.shared.signingOut() }
        _auth = State(initialValue: auth)
        // More translations to download (none in UI tests).
        library.setDownloader(TranslationDownloader(client: testing.isEnabled ? nil : auth.client))
        _sync = State(initialValue: sync)

        // UI tests never reach StoreKit: Premium is on only with -uiTestingPremium.
        let entitlements = EntitlementService(override: testing.isEnabled ? testing.isPremium : nil)
        sync.isAllowed = { [weak entitlements] in entitlements?.allows(.cloudBackup) ?? false }
        _entitlements = State(initialValue: entitlements)

        // UI tests get canned answers: no network and no AI cost.
        let backend: StudyAssistantBackend? = testing.isEnabled ? StubStudyBackend() : StudyAssistant.liveBackend(client: auth.client)
        // Server-side switches (Supabase feature_flags). UI tests never ask the
        // server: the assistant is on only with -uiTestingAI.
        let flags = FeatureFlagService(
            client: testing.isEnabled ? nil : auth.client,
            override: testing.isEnabled ? [.studyAssistant: testing.enablesAI, .groups: true, .community: true] : nil
        )
        _flags = State(initialValue: flags)
        _whatsNew = State(initialValue: WhatsNewService(isEnabled: !testing.isEnabled || testing.showsWhatsNew))
        _assistant = State(initialValue: StudyAssistant(auth: auth, entitlements: entitlements, library: library, backend: backend, flags: flags, preferences: features))

        // Listening. UI tests use a silent narrator that moves through verses
        // on a timer, and no recorded narration.
        let audioSettings = AudioSettings()
        let audio = AudioPlayerService(
            library: library,
            settings: audioSettings,
            catalog: AudioRecordingCatalog(client: testing.isEnabled ? nil : auth.client),
            narrator: testing.isEnabled ? StubNarrator() : SpeechNarrator()
        )
        audio.onPosition = { [weak reader, weak audioSettings] chapter, verse in
            reader?.audioMoved(chapter: chapter, verse: verse, follow: audioSettings?.followsAlong ?? true)
        }
        // The Lock Screen Live Activity is a Premium widget; never in UI tests.
        let testingEnabled = testing.isEnabled
        audio.liveActivity.isAllowed = { [weak entitlements, weak features] in
            !testingEnabled && entitlements?.allows(.widgets) == true && features?.isOn(.listen) == true
        }
        _audio = State(initialValue: audio)
        // Ambient sounds: silent in UI tests.
        _ambient = State(initialValue: AmbientSoundService(output: testing.isEnabled ? SilentAmbientOutput() : EngineAmbientOutput()))

        // Groups and the community. UI tests use an in-memory server with a
        // signed-in person (or none with -uiTestingSignedOut).
        let communityBackend: CommunityBackend
        if testing.isEnabled {
            communityBackend = testing.isSignedOut ? SignedOutCommunityBackend() as CommunityBackend : InMemoryCommunityBackend()
        } else if let client = auth.client {
            communityBackend = SupabaseCommunityBackend(client: client, auth: auth)
        } else {
            communityBackend = SignedOutCommunityBackend()
        }
        _community = State(initialValue: CommunityStore(backend: communityBackend))
        let push = PushNotifications.shared
        push.isEnabled = !testing.isEnabled
        push.backend = communityBackend
        push.onOpenGroup = { [weak router] id in router?.openGroup(id) }
        push.onOpenPrayerJournal = { [weak router] in router?.open(.prayerJournal) }

        GenesisTips.configure(testing: testing.isEnabled)
        testing.apply(settings: settings, router: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(settings)
                .environment(progress)
                .environment(reader)
                .environment(router)
                .environment(auth)
                .environment(sync)
                .environment(entitlements)
                .environment(assistant)
                .environment(flags)
                .environment(whatsNew)
                .environment(audio)
                .environment(ambient)
                .environment(community)
                .environment(features)
                .environment(\.studyData, studyData)
                .environment(\.topics, topics)
        }
        .modelContainer(modelContainer)
    }

    /// On-device store for highlights, notes and bookmarks. If the store can't
    /// be opened, fall back to memory so the Bible still opens.
    private static func makeModelContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema(UserDataSchema.models)
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
        } catch {
            CrashReporter.record(error, context: "ModelContainer")
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            } catch {
                fatalError("Could not create even an in-memory store: \(error)")
            }
        }
    }
}
