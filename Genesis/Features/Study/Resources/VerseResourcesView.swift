import SwiftUI

/// The downloaded study helps for one verse: study notes, related articles
/// and key terms, and the chosen commentary. The verse is shown verbatim
/// from the Bible being read; everything else is labelled with its source.
struct VerseResourcesView: View {
    let verse: VerseID
    var onOpenVerse: ((VerseID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VerseResourcesList(verse: verse, onOpenVerse: onOpenVerse)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                            .accessibilityIdentifier("verseResources.done")
                    }
                }
                .navigationDestination(for: StudyArticleRoute.self) { route in
                    StudyArticleView(pack: route.pack, articleID: route.id, onOpenVerse: onOpenVerse)
                }
                .navigationDestination(for: StudyIntroductionRoute.self) { route in
                    StudyIntroductionView(route: route, onOpenVerse: onOpenVerse)
                }
        }
    }
}

struct StudyIntroductionRoute: Hashable {
    let pack: String
    let book: Int
}

private struct VerseResourcesList: View {
    let verse: VerseID
    let onOpenVerse: ((VerseID) -> Void)?

    enum Tab: String, CaseIterable, Identifiable {
        case notes, commentary
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notes: String(localized: "Notes", comment: "Tab: study notes and articles on a verse")
            case .commentary: String(localized: "Commentary")
            }
        }
    }

    /// What one pack has on the verse.
    struct PackResult: Identifiable, Sendable {
        let resource: DownloadableStudyResource
        let hasIntroduction: Bool
        let notes: [StudyNote]
        let articles: [StudyArticleSummary]
        var id: String { resource.id }
        var isEmpty: Bool { notes.isEmpty && articles.isEmpty && !hasIntroduction }
    }

    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(BibleLibrary.self) private var library
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @State private var tab: Tab = .notes
    @State private var notes: [PackResult]?
    @State private var commentary: PackResult?
    @State private var loadedCommentary: String?
    @State private var showsLibrary = false

    private var allowsPremium: Bool { entitlements.allows(.wordStudy) }

    private var language: String { library.currentTranslation.language }

    /// The notes packs and dictionaries (key terms link to verses), free first.
    private var notePacks: [DownloadableStudyResource] {
        (resources.installedResources(.notes) + resources.installedResources(.dictionary))
            .filter { allowsPremium || !$0.premium }
    }

    private var commentaries: [DownloadableStudyResource] { resources.installedResources(.commentary) }

    private var currentCommentary: DownloadableStudyResource? {
        resources.commentary(allowsPremium: allowsPremium)
    }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    Text((try? library.current.verse(verse))?.plainText ?? "")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("verseResources.verse")
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("verseResources.tab")
                }

                switch tab {
                case .notes: notesSections
                case .commentary: commentarySections
                }

                Section {
                    Button {
                        showsLibrary = true
                    } label: {
                        Label("Study Library", systemImage: "books.vertical")
                            .foregroundStyle(palette.accent)
                    }
                    .accessibilityIdentifier("verseResources.library")
                } footer: {
                    if AppLanguage.code != "en" || language != "en" {
                        Text("Most study resources are in English for now.")
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(PassageReference(verse: verse).description(in: language))
        .navigationBarTitleDisplayMode(.inline)
        .studyLinks(onOpenVerse: onOpenVerse)
        .sheet(isPresented: $showsLibrary) {
            StudyResourcesView()
        }
        .task(id: LoadKey(verse: verse, packs: notePacks.map(\.id) + [currentCommentary?.id ?? ""])) { await load() }
    }

    private struct LoadKey: Hashable {
        let verse: VerseID
        let packs: [String]
    }

    // MARK: Notes

    @ViewBuilder
    private var notesSections: some View {
        if notePacks.isEmpty {
            getStarted(String(localized: "Download study notes or a Bible dictionary from the Study Library to see notes on this verse."))
        } else if let notes {
            if notes.allSatisfy(\.isEmpty) {
                Section {
                    Text("There are no notes on this verse.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
            ForEach(notes.filter { !$0.isEmpty }) { result in
                packSections(result)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func packSections(_ result: PackResult) -> some View {
        ForEach(result.notes) { note in
            noteSection(note, resource: result.resource)
        }
        if result.hasIntroduction || !result.articles.isEmpty {
            Section {
                if result.hasIntroduction {
                    NavigationLink(value: StudyIntroductionRoute(pack: result.resource.id, book: verse.book)) {
                        Label(String(localized: "Introduction to \(BibleBook.withNumber(verse.book).name(in: language))"), systemImage: "text.book.closed")
                            .foregroundStyle(palette.text)
                    }
                }
                ForEach(result.articles) { article in
                    NavigationLink(value: StudyArticleRoute(pack: result.resource.id, id: article.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title).foregroundStyle(palette.text)
                            if let kind = StudyArticleKind.title(article.kind) {
                                Text(kind)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            } header: {
                Text(result.resource.kind == .dictionary ? result.resource.name : String(localized: "More from \(result.resource.name)"))
            }
        }
    }

    private func noteSection(_ note: StudyNote, resource: DownloadableStudyResource) -> some View {
        Section {
            StudyTextRows(text: note.text)
        } header: {
            Text(note.title.map { "\(note.range.description(in: language)) · \($0)" } ?? note.range.description(in: language))
        } footer: {
            Text(resource.author.isEmpty ? resource.name : "\(resource.name) · \(resource.author)")
        }
    }

    // MARK: Commentary

    @ViewBuilder
    private var commentarySections: some View {
        if commentaries.isEmpty {
            getStarted(String(localized: "Download a commentary from the Study Library to read it beside every verse."))
        } else if let current = currentCommentary {
            Section {
                commentaryPicker(current)
            }
            if let commentary, commentary.resource.id == current.id {
                if commentary.notes.isEmpty {
                    Section {
                        Text("\(current.name) has no comment on this verse.")
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                ForEach(commentary.notes) { note in
                    noteSection(note, resource: current)
                }
                Section {
                } footer: {
                    Text("A commentary is one writer's explanation, shown apart from Scripture.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } else {
            Section {
                PremiumTeaser(message: String(localized: "Read the classic commentaries beside every verse with Premium."), feature: .wordStudy)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
    }

    private func commentaryPicker(_ current: DownloadableStudyResource) -> some View {
        let choices = commentaries.filter { allowsPremium || !$0.premium }
        let selection = Binding(get: { current.id }, set: { resources.chosenCommentaryID = $0 })
        return Picker("Commentary", selection: selection) {
            ForEach(choices) { item in
                Text(item.name).tag(item.id)
            }
        }
        .pickerStyle(.menu)
        .tint(palette.accent)
        .accessibilityIdentifier("verseResources.commentary")
    }

    private func getStarted(_ message: String) -> some View {
        Section {
            Text(message)
                .foregroundStyle(palette.secondaryText)
            Button("Open Study Library") { showsLibrary = true }
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("verseResources.getStarted")
        }
    }

    // MARK: Loading

    /// Packs number verses as the KJV does; the Reina-Valera differs in places.
    private var kjvVerse: VerseID {
        OriginalVersification.map(for: library.currentTranslation.id)?.alignment(of: verse).kjv.first ?? verse
    }

    private func load() async {
        let target = kjvVerse
        let packs = notePacks.compactMap { item in resources.repository(item.id).map { (item, $0) } }
        let chosen = currentCommentary.flatMap { item in resources.repository(item.id).map { (item, $0) } }
        let loaded = await Task.detached(priority: .userInitiated) {
            let notes = packs.map { item, repository in
                PackResult(
                    resource: item,
                    hasIntroduction: (try? repository.introduction(toBook: target.book)) != nil,
                    notes: (try? repository.notes(for: target)) ?? [],
                    articles: (try? repository.articles(for: target)) ?? []
                )
            }
            let commentary = chosen.map { item, repository in
                PackResult(resource: item, hasIntroduction: false, notes: (try? repository.notes(for: target)) ?? [], articles: [])
            }
            return (notes, commentary)
        }.value
        notes = loaded.0
        commentary = loaded.1
    }
}

/// A book's introduction from a study pack.
struct StudyIntroductionView: View {
    let route: StudyIntroductionRoute
    var onOpenVerse: ((VerseID) -> Void)?

    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @State private var introduction: StudyIntroduction?

    var body: some View {
        List {
            ThemedRows {
                if let introduction {
                    Section {
                        StudyTextRows(text: introduction.text)
                    } footer: {
                        if let resource = resources.resource(route.pack) {
                            Text(resource.attribution.isEmpty ? resource.name : resource.attribution)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .themedScreen()
        .navigationTitle(introduction?.title ?? BibleBook.withNumber(route.book).name(in: library.currentTranslation.language))
        .navigationBarTitleDisplayMode(.inline)
        .studyLinks(onOpenVerse: onOpenVerse)
        .task {
            guard let repository = resources.repository(route.pack) else { return }
            let book = route.book
            introduction = await Task.detached(priority: .userInitiated) {
                try? repository.introduction(toBook: book)
            }.value
        }
    }
}
