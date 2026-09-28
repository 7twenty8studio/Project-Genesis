import SwiftData
import SwiftUI

@main
struct GenesisApp: App {
    @State private var library: BibleLibrary
    @State private var settings: ReaderSettings
    @State private var progress: ReadingProgress
    @State private var reader: ReaderViewModel
    @State private var router: AppRouter
    private let modelContainer: ModelContainer

    init() {
        CrashReporter.start()

        let library = BibleLibrary()
        let progress = ReadingProgress()
        let reader = ReaderViewModel(library: library, progress: progress)
        _library = State(initialValue: library)
        _settings = State(initialValue: ReaderSettings())
        _progress = State(initialValue: progress)
        _reader = State(initialValue: reader)
        _router = State(initialValue: AppRouter(reader: reader))
        modelContainer = Self.makeModelContainer()
        // Available before the first page draws, so highlights show immediately.
        reader.modelContext = modelContainer.mainContext
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(settings)
                .environment(progress)
                .environment(reader)
                .environment(router)
        }
        .modelContainer(modelContainer)
    }

    /// On-device store for highlights, notes and bookmarks. If the store can't
    /// be opened, fall back to memory so the Bible still opens.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(UserDataSchema.models)
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
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
