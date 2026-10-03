import SwiftData
import SwiftUI

/// Memorise Scripture (Premium): the passages being learned, what's due for
/// review today, and a way to add more.
struct MemoriseView: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \MemoryVerse.dueAt) private var verses: [MemoryVerse]

    @State private var session: MemorySession?
    @State private var showsAdd = false
    @State private var newReference = ""
    @State private var addError: String?

    private var due: [MemoryVerse] { verses.filter { $0.isDue() } }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    summary
                }

                if verses.isEmpty {
                    QuietEmptyState(
                        systemImage: "brain.head.profile",
                        title: String(localized: "Hide God's word in your heart"),
                        message: String(localized: "Add a verse, then review it for a minute a day. Each time you remember it, the next review comes a little later.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Your Verses") {
                        ForEach(verses) { verse in
                            Button {
                                session = MemorySession(cards: [verse.id])
                            } label: {
                                MemoryRow(verse: verse, translation: translation(for: verse))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("memorise.verse.\(verse.startRaw)")
                        }
                        .onDelete { offsets in
                            let store = StudyStore(context: modelContext)
                            for index in offsets { store.delete(verses[index]) }
                        }
                    }
                }

                let suggestions = MemoriseSuggestions.all.filter { suggestion in
                    !verses.contains { $0.startRaw == suggestion.start.rawValue }
                }
                if !suggestions.isEmpty && verses.count < 12 {
                    Section {
                        ForEach(suggestions.prefix(verses.isEmpty ? 8 : 3), id: \.start) { suggestion in
                            Button {
                                StudyStore(context: modelContext).memorise(from: suggestion.start, through: suggestion.end, translationID: library.currentTranslation.id)
                            } label: {
                                HStack {
                                    Text(suggestion.reference.description)
                                        .foregroundStyle(palette.text)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(palette.accent)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(suggestion.reference.description)")
                            .accessibilityIdentifier("memorise.suggestion.\(suggestion.start.rawValue)")
                        }
                    } header: {
                        Text("Verses to Start With")
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Memorise")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Verse", systemImage: "plus") {
                    newReference = ""
                    showsAdd = true
                }
                .accessibilityIdentifier("memorise.add")
            }
        }
        .alert("Add a Verse", isPresented: $showsAdd) {
            TextField(String(localized: "John 3:16", comment: "Example Bible reference"), text: $newReference)
                .autocorrectionDisabled()
                .accessibilityIdentifier("memorise.reference")
            Button("Add") { add(newReference) }
                .accessibilityIdentifier("memorise.addConfirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a reference, such as Psalm 23:1\u{2013}3.")
        }
        .alert("Couldn't Add That", isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addError ?? "")
        }
        .fullScreenCover(item: $session) { session in
            MemoryReviewView(session: session)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(due.isEmpty ? String(localized: "All caught up") : String(localized: "\(due.count) to review today"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("memorise.dueCount")
                    let memorised = verses.filter { $0.mastery == .memorised }.count
                    Text("\(verses.count) verses · \(memorised) memorised")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
            if !due.isEmpty {
                Button {
                    session = MemorySession(cards: due.map(\.id))
                } label: {
                    Text("Review Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.review")
            }
        }
        .padding(.vertical, 6)
    }

    private func translation(for verse: MemoryVerse) -> Translation {
        library.translations.first { $0.id == verse.translationID } ?? library.currentTranslation
    }

    private func add(_ text: String) {
        guard let reference = ReferenceParser.parse(text), reference.chapter != nil, let first = reference.verseStart else {
            addError = String(localized: "Type a book, chapter and verse, such as John 3:16.")
            return
        }
        let start = VerseID(book: reference.book.id, chapter: reference.chapter ?? 1, verse: first)
        let end = VerseID(book: reference.book.id, chapter: reference.chapter ?? 1, verse: max(first, reference.verseEnd ?? first))
        guard end.verse - start.verse < MemoriseSuggestions.maximumVerses else {
            addError = String(localized: "Choose up to \(MemoriseSuggestions.maximumVerses) verses at a time.")
            return
        }
        guard (try? library.current.verse(start)) != nil else {
            addError = String(localized: "That verse isn't in this Bible.")
            return
        }
        StudyStore(context: modelContext).memorise(from: start, through: end, translationID: library.currentTranslation.id)
    }
}

/// One passage in the list: reference, how well it's known and when it's next due.
private struct MemoryRow: View {
    let verse: MemoryVerse
    let translation: Translation

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(palette.separator, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.04, verse.mastery.fraction))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verse.reference.description)
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.text)
                Text("\(translation.abbreviation) · \(verse.mastery.title)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Text(dueText)
                .font(.caption)
                .foregroundStyle(verse.isDue() ? palette.accent : palette.secondaryText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        if verse.isDue() { return String(localized: "Due", comment: "Memorise: ready to review now") }
        return verse.dueAt.formatted(.relative(presentation: .named))
    }
}

/// Some well-loved passages to begin with (references only).
enum MemoriseSuggestions {
    struct Suggestion: Sendable {
        let start: VerseID
        let end: VerseID
        var reference: PassageReference { PassageReference(verses: [start, end]) ?? PassageReference(verse: start) }
    }

    static let maximumVerses = 15

    private static func s(_ book: Int, _ chapter: Int, _ first: Int, _ last: Int? = nil) -> Suggestion {
        Suggestion(start: VerseID(book: book, chapter: chapter, verse: first), end: VerseID(book: book, chapter: chapter, verse: last ?? first))
    }

    static let all: [Suggestion] = [
        s(43, 3, 16),     // John 3:16
        s(19, 119, 105),  // Psalm 119:105
        s(20, 3, 5, 6),   // Proverbs 3:5–6
        s(6, 1, 9),       // Joshua 1:9
        s(23, 40, 31),    // Isaiah 40:31
        s(40, 11, 28),    // Matthew 11:28
        s(45, 8, 28),     // Romans 8:28
        s(50, 4, 6, 7),   // Philippians 4:6–7
        s(19, 23, 1),     // Psalm 23:1
        s(46, 13, 4, 7),  // 1 Corinthians 13:4–7
    ]
}

/// A set of cards to review, by id (opened as a full-screen cover).
struct MemorySession: Identifiable, Hashable {
    let id = UUID()
    let cards: [UUID]
}
