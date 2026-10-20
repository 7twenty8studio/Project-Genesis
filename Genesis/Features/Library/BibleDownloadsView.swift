import SwiftUI

/// The Global Reading Library: every Bible by language, the most read first,
/// each with how it's translated, how it reads, its audio and its rights, and
/// a guide to choosing. Bibles on the device work offline; downloads are
/// updated automatically when a corrected edition comes out.
struct BibleDownloadsView: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AuthService.self) private var auth
    @Environment(ReaderViewModel.self) private var reader
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var chosenLanguage: String?
    @State private var removing: Translation?
    @State private var hasLoaded = false
    @State private var showsGuide = false
    @State private var premium: PremiumFeature?

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

                    downloads
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
            .premiumSheet($premium)
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
            // A failed download says so where it can't be missed (the
            // footer sits below a long list).
            .alert(
                String(localized: "Couldn't download"),
                isPresented: Binding(get: { library.downloadError != nil }, set: { if !$0 { library.downloadError = nil } })
            ) {
                Button(String(localized: "OK")) { library.downloadError = nil }
            } message: {
                Text(library.downloadError ?? "")
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

    /// Bibles downloading now or paused partway, in every language, so a
    /// download can be watched and continued from one place.
    private var activeDownloads: [DownloadableTranslation] {
        library.catalog.filter { library.downloading.contains($0.id) || library.savedBooks(for: $0) > 0 }
    }

    @ViewBuilder
    private var downloads: some View {
        let items = activeDownloads
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    DownloadProgressRow(
                        item: item,
                        isDownloading: library.downloading.contains(item.id),
                        progress: library.downloadProgress[item.id],
                        savedBooks: library.savedBooks(for: item),
                        resume: { Task { await library.download(item) } },
                        discard: { library.discardDownload(item) }
                    )
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("A paused download keeps what it has for a week. Continue it any time.")
            }
            .listRowBackground(palette.surface)
        }
    }

    private var bibles: some View {
        Section {
            ForEach(entries) { entry in
                TranslationCardView(
                    entry: entry,
                    isCurrent: entry.translation.id == library.currentTranslation.id,
                    isDownloading: library.downloading.contains(entry.id),
                    progress: library.downloadProgress[entry.id],
                    savedBooks: entry.download.map { library.savedBooks(for: $0) } ?? 0,
                    read: {
                        if library.isLocked(entry.translation) {
                            premium = .premiumBibles
                        } else {
                            reader.switchTranslation(to: entry.translation)
                        }
                    },
                    download: {
                        // A Premium Bible is downloaded only with Premium.
                        if library.isLocked(entry.translation) {
                            premium = .premiumBibles
                            return
                        }
                        guard let item = entry.download else { return }
                        Task {
                            if item.premium {
                                library.premiumProof = PremiumProof(accessToken: try? await auth.accessToken(), signedTransaction: entitlements.signedTransaction)
                            }
                            await library.download(item)
                        }
                    },
                    discard: entry.download.map { item in { library.discardDownload(item) } }
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
            VStack(alignment: .leading, spacing: 4) {
                Text("The most read are listed first.")
                Text("Every Bible here is public domain or used with its publisher's permission.")
            }
        }
        .listRowBackground(palette.surface)
    }
}

/// One download in the Bibles screen's Downloads section: a bar while it
/// runs, or what's saved and a Continue button when it's paused.
private struct DownloadProgressRow: View {
    let item: DownloadableTranslation
    let isDownloading: Bool
    let progress: Double?
    let savedBooks: Int
    let resume: () -> Void
    let discard: () -> Void

    @Environment(\.palette) private var palette

    private static let bookCount = YouVersionBibleBuilder.bookCodes.count
    private var savedBookCount: Int { savedBooks }
    private var doneCount: Int { Int(((progress ?? 0) * Double(Self.bookCount)).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                if isDownloading {
                    Text(String(localized: "Downloading"))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                } else {
                    Button(String(localized: "Discard"), role: .destructive, action: discard)
                        .font(.caption)
                        .buttonStyle(.borderless)
                    Button(String(localized: "Continue"), action: resume)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(palette.accent)
                        .accessibilityLabel(String(localized: "Continue downloading \(item.name)"))
                }
            }
            if isDownloading, progress == nil {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if isDownloading {
                ProgressView(value: progress ?? 0).tint(palette.accent)
                Text(String(localized: "Downloading · \(doneCount) of \(Self.bookCount) books"))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            } else {
                ProgressView(value: Double(savedBooks), total: Double(Self.bookCount)).tint(palette.secondaryText)
                Text(String(localized: "Paused · \(savedBookCount) of \(Self.bookCount) books saved"))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("bibles.downloadRow.\(item.id)")
    }
}
