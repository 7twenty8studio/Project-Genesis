import SwiftUI

/// What to read in a reading challenge: a book (all of it or a chapter
/// range), or several whole books.
struct ChallengeReadingPicker: View {
    @Binding var selection: ReadingChallengeSelection

    @Environment(\.palette) private var palette

    private var bookBinding: Binding<Int> {
        Binding(
            get: { selection.books.first ?? 41 },
            set: { selection.choose(book: $0) }
        )
    }

    var body: some View {
        Section {
            if selection.isSingleBook {
                Picker("Book", selection: bookBinding) {
                    ForEach(BibleBook.all) { book in
                        Text(book.name).tag(book.id)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("newChallenge.book")
                chapterRange
            } else {
                Text(selection.name)
                    .foregroundStyle(palette.text)
            }
            NavigationLink {
                ChallengeBooksPicker(selection: $selection)
            } label: {
                Label(selection.isSingleBook ? "Choose Several Books" : "Change Books", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("newChallenge.books")
        } header: {
            Text("What to Read")
        } footer: {
            Text(chapterCountLine)
        }
    }

    @ViewBuilder
    private var chapterRange: some View {
        let count = BibleBook.withNumber(selection.books.first ?? 41).chapterCount
        if count > 1 {
            Stepper(value: $selection.firstChapter, in: 1...max(1, selection.lastChapter)) {
                Text("From chapter \(selection.firstChapter)")
            }
            Stepper(value: $selection.lastChapter, in: min(selection.firstChapter, count)...count) {
                Text("To chapter \(selection.lastChapter)")
            }
        }
    }

    private var chapterCountLine: String {
        let count = selection.chapters.count
        return count == 1 ? String(localized: "1 chapter") : String(localized: "\(count) chapters")
    }
}

/// Several whole books for a reading challenge.
private struct ChallengeBooksPicker: View {
    @Binding var selection: ReadingChallengeSelection

    @Environment(\.palette) private var palette
    @State private var chosen: Set<Int> = []

    var body: some View {
        List {
            ThemedRows {
                ForEach(Testament.allCases, id: \.self) { testament in
                    Section(testament.title) {
                        ForEach(testament == .old ? BibleBook.oldTestament : BibleBook.newTestament) { book in
                            row(book)
                        }
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Books")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { chosen = Set(selection.books) }
        .onChange(of: chosen) { _, newValue in
            selection.choose(books: newValue)
        }
    }

    private func row(_ book: BibleBook) -> some View {
        let isChosen = chosen.contains(book.id)
        return Button {
            if isChosen {
                // Keep at least one book.
                if chosen.count > 1 { chosen.remove(book.id) }
            } else {
                chosen.insert(book.id)
            }
        } label: {
            HStack {
                Text(book.name).foregroundStyle(palette.text)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// The passage for a memorise challenge: typed, or one of Memorise's
/// suggestions, with its words shown verbatim from the Bible being read.
struct ChallengePassagePicker: View {
    @Binding var text: String

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            TextField(String(localized: "Psalm 23:1\u{2013}3", comment: "Example Bible passage"), text: $text)
                .autocorrectionDisabled()
                .accessibilityIdentifier("newChallenge.passage")
            Menu {
                ForEach(MemoriseSuggestions.all, id: \.start) { suggestion in
                    Button(suggestion.reference.description) {
                        text = suggestion.reference.description
                    }
                }
            } label: {
                Label("Suggestions", systemImage: "lightbulb")
            }
            .accessibilityIdentifier("newChallenge.suggestions")
            preview
        } header: {
            Text("Passage")
        } footer: {
            let maximumVerses = GroupChallengeRules.maximumVerses
            Text("Up to \(maximumVerses) verses from one chapter, in the Bible you're reading.")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let passage = ChallengePassage.parse(text) {
            let verses = (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
            if verses.isEmpty {
                Text("That passage isn't in the Bible you're reading.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text(verses.map(\.plainText).joined(separator: " "))
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(palette.text)
            }
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Type a book, chapter and verses, such as Psalm 23:1\u{2013}3.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }
}
