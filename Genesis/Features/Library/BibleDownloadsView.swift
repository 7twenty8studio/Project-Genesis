import SwiftUI

/// The Global Reading Library: every Bible by language, the most read first,
/// each with how it's translated, how it reads, its audio and its rights, and
/// a guide to choosing. Bibles on the device work offline; downloads are
/// updated automatically when a corrected edition comes out.
struct BibleDownloadsView: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderViewModel.self) private var reader
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var chosenLanguage: String?
    @State private var removing: Translation?
    @State private var hasLoaded = false
    @State private var showsGuide = false

    private var languages: [String] {
        ReadingLibrary.languages(installed: library.translations, catalog: library.catalog, preferred: AppLanguage.code)
    }

    /// The language picked here; otherwise the app's language when it has a
    /// Bible, else the language of the Bible being read.
    private var language: String {
        if let chosenLanguage, languages.contains(chosenLanguage) { return chosenLanguage }
        return languages.contains(AppLanguage.code) ? AppLanguage.code : library.currentTranslation.language
    }

    private var entries: [LibraryEntry] {
        ReadingLibrary.entries(
            in: language,
            installed: library.translations,
            catalog: library.catalog,
            recordedTranslationIDs: Set(audio.catalog.recordings.map(\.translation))
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section {
                        if languages.count > 1 {
                            languagePicker
                        }
                        Button {
                            showsGuide = true
                        } label: {
                            Label("Which Bible is right for me?", systemImage: "questionmark.circle")
                                .foregroundStyle(palette.accent)
                        }
                        .accessibilityIdentifier("bibles.guide")
                    } footer: {
                        Text("Every Bible here is free, and works offline once it's on your device.")
                    }
                    .listRowBackground(palette.surface)

                    bibles
                }
            }
            .themedScreen()
            .navigationTitle("Bibles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("bibles.done")
                }
            }
            .task {
                await library.refreshCatalog()
                hasLoaded = true
            }
            .sheet(isPresented: $showsGuide) {
                TranslationGuideView(language: language)
            }
            .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let removing { library.remove(removing) }
                }
            } message: {
                Text("Your highlights and notes stay. You can download it again any time.")
            }
        }
    }

    // MARK: Parts

    private var languagePicker: some View {
        let selection = Binding(get: { language }, set: { chosenLanguage = $0 })
        return Group {
            if languages.count <= 3 {
                Picker("Language", selection: selection) {
                    ForEach(languages, id: \.self) { Text(AppLanguage.displayName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Language", selection: selection) {
                    ForEach(languages, id: \.self) { Text(AppLanguage.displayName($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(palette.accent)
            }
        }
        .accessibilityIdentifier("bibles.language")
    }

    private var bibles: some View {
        Section {
            ForEach(entries) { entry in
                TranslationCardView(
                    entry: entry,
                    isCurrent: entry.translation.id == library.currentTranslation.id,
                    isDownloading: library.downloading.contains(entry.id),
                    read: { reader.switchTranslation(to: entry.translation) },
                    download: {
                        guard let item = entry.download else { return }
                        Task { await library.download(item) }
                    }
                )
                .swipeActions {
                    if library.isRemovable(entry.translation) {
                        Button("Remove", role: .destructive) { removing = entry.translation }
                    }
                }
                .contextMenu {
                    if library.isRemovable(entry.translation) {
                        Button("Remove from This Device", systemImage: "trash", role: .destructive) { removing = entry.translation }
                    }
                }
            }
            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if library.catalog.isEmpty {
                Text("Connect to the internet to see more Bibles.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text(AppLanguage.displayName(language))
        } footer: {
            if let error = library.downloadError {
                Text(error).foregroundStyle(.orange)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The most read are listed first.")
                    Text("Genesis offers public-domain translations. More will come as licenses allow.")
                }
            }
        }
        .listRowBackground(palette.surface)
    }
}
