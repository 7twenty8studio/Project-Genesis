import SwiftUI

/// A study text's paragraphs, one row each (some commentaries run to
/// thousands of words on a passage). Links open with `.studyLinks`.
struct StudyTextRows: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        ForEach(Array(StudyMarkup.blocks(text).enumerated()), id: \.offset) { _, block in
            switch block {
            case let .heading(inline):
                Text(StudyMarkup.attributed(inline))
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
            case let .listItem(inline):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\u{2022}")
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    Text(StudyMarkup.attributed(inline))
                        .foregroundStyle(palette.text)
                }
            case let .paragraph(inline):
                Text(StudyMarkup.attributed(inline))
                    .foregroundStyle(palette.text)
            }
        }
        .textSelection(.enabled)
    }
}

extension StudyRange: Identifiable {
    var id: String { "\(start.rawValue)-\(end.rawValue)" }
}

/// An article link's target.
struct StudyArticleRoute: Hashable, Identifiable {
    let pack: String
    let id: String
}

extension View {
    /// Opens verse links in a passage preview (verbatim from the Bible being
    /// read, with "Open in Reader" when `onOpenVerse` is given) and article
    /// links in their article.
    func studyLinks(onOpenVerse: ((VerseID) -> Void)? = nil) -> some View {
        modifier(StudyLinksModifier(onOpenVerse: onOpenVerse))
    }
}

private struct StudyLinksModifier: ViewModifier {
    let onOpenVerse: ((VerseID) -> Void)?

    @State private var passage: StudyRange?
    @State private var article: StudyArticleRoute?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                switch StudyMarkup.link(url) {
                case let .verses(range):
                    passage = range
                    return .handled
                case let .article(pack, id):
                    article = StudyArticleRoute(pack: pack, id: id)
                    return .handled
                case nil:
                    // Packs only link to verses and articles.
                    return .discarded
                }
            })
            .sheet(item: $passage) { range in
                StudyPassageSheet(range: range, onOpen: onOpenVerse.map { open in
                    { verse in
                        passage = nil
                        open(verse)
                    }
                })
            }
            .sheet(item: $article) { route in
                NavigationStack {
                    StudyArticleView(pack: route.pack, articleID: route.id, onOpenVerse: onOpenVerse.map { open in
                        { verse in
                            article = nil
                            open(verse)
                        }
                    })
                    .studyDoneButton()
                }
            }
    }
}

/// The verses a link points to, verbatim from the Bible being read.
struct StudyPassageSheet: View {
    let range: StudyRange
    let onOpen: ((VerseID) -> Void)?

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// Long links (a whole book) show their opening verses.
    private static let verseLimit = 40

    var body: some View {
        let verses = Array(((try? library.current.verses(from: range.start, through: range.end)) ?? []).prefix(Self.verseLimit))
        NavigationStack {
            List {
                ThemedRows {
                    Section {
                        if verses.isEmpty {
                            Text("This passage isn't in \(library.currentTranslation.name).")
                                .foregroundStyle(palette.secondaryText)
                        }
                        ForEach(verses) { verse in
                            VerseSnippet(
                                reference: PassageReference(verse: verse.id).description(in: library.currentTranslation.language),
                                text: verse.plainText,
                                lineLimit: nil
                            )
                        }
                    } footer: {
                        Text(library.currentTranslation.name)
                    }
                }
            }
            .themedScreen()
            .navigationTitle(range.description(in: library.currentTranslation.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
                if let onOpen, let first = verses.first {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Open in Reader", systemImage: "book") { onOpen(first.id) }
                            .accessibilityIdentifier("studyPassage.open")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// A Done button for a study sheet's navigation stack.
    func studyDoneButton() -> some View {
        modifier(StudyDoneButton())
    }
}

private struct StudyDoneButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
            }
        }
    }
}
