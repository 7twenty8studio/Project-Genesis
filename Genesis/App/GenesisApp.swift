import SwiftData
import SwiftUI

@main
struct GenesisApp: App {
    @State private var library: BibleLibrary
    @State private var settings: ReaderSettings
    @State private var progress: ReadingProgress
    @State private var reader: ReaderViewModel
    @State private var router: AppRouter
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var entitlements: EntitlementService
    private let modelContainer: ModelContainer

    init() {
        let testing = UITestingOptions.current
        if testing.isEnabled {
            testing.resetPersistentState()
        } else {
            CrashReporter.start()
        }

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
        auth.onSignIn = { [weak sync] user in sync?.accountDidSignIn(user) }
        _auth = State(initialValue: auth)
        _sync = State(initialValue: sync)

        // UI tests never reach StoreKit: Premium is on only with -uiTestingPremium.
        let entitlements = EntitlementService(override: testing.isEnabled ? testing.isPremium : nil)
        sync.isAllowed = { [weak entitlements] in entitlements?.allows(.cloudBackup) ?? false }
        _entitlements = State(initialValue: entitlements)

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
