import SwiftUI

/// Church Mode's "Look up a verse": type "John 3:16" (or "Juan 3:16") to see
/// the words verbatim from the Bible being read; Insert puts the reference
/// in the notes and attaches the passage.
struct SermonVerseLookup: View {
    let canAttach: Bool
    let onInsert: (PrayerPassage, String) -> Void

    @Environment(BibleLibrary.self) private var library
    @State private var text = ""

    var body: some View {
        Section {
            TextField(String(localized: "John 3:16", comment: "Example Bible reference"), text: $text)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("sermon.lookupField")
            result
        } header: {
            Text("Look Up a Verse")
        } footer: {
            Text("Insert adds the reference to your notes and attaches the passage.")
        }
    }

    @ViewBuilder
    private var result: some View {
        switch SermonPassageResolver.resolve(text, in: library.current) {
        case .empty:
            EmptyView()
        case .notAReference:
            Text("Type a book, chapter and verse, such as John 3:16.")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case .notInBible:
            Text("That passage isn't in the Bible you're reading.")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case let .found(passage):
            VStack(alignment: .leading, spacing: 10) {
                SermonPassageText(passage: passage)
                Button {
                    let reference = passage.reference.description(in: library.currentTranslation.language)
                    onInsert(passage, reference)
                    text = ""
                } label: {
                    Label("Insert into Notes", systemImage: "text.insert")
                }
                .buttonStyle(.borderless)
                .disabled(!canAttach)
                .accessibilityIdentifier("sermon.lookupInsert")
            }
        }
    }
}

/// The passages a sermon holds, each shown verbatim from the Bible being
/// read; tap one to open it in the reader. A field adds another.
struct SermonPassagesSection: View {
    let sermon: Sermon
    let onOpen: (PrayerPassage) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(sermon.passages) { passage in
                Button {
                    onOpen(passage)
                } label: {
                    SermonPassageText(passage: passage)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in the reader")
                .accessibilityIdentifier("sermon.passage")
            }
            .onDelete { offsets in
                let store = StudyStore(context: modelContext)
                offsets.map { sermon.passages[$0] }.forEach { store.detach($0, from: sermon) }
            }
            if sermon.passages.count < Sermon.maximumPassages {
                HStack {
                    TextField(String(localized: "John 3:16", comment: "Example Bible reference"), text: $text)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("sermon.passageField")
                    Button("Add", action: add)
                        .buttonStyle(.borderless)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("sermon.addPassage")
                }
            }
        } header: {
            Text("Bible Passages")
        } footer: {
            if let problem {
                Text(problem)
                    .foregroundStyle(.orange)
            } else {
                Text("Add the passages the sermon was about, such as Romans 8:28\u{2013}39.")
            }
        }
    }

    private func add() {
        switch SermonPassageResolver.resolve(text, in: library.current) {
        case .empty:
            return
        case .notAReference:
            problem = String(localized: "Type a book, chapter and verse, such as John 3:16.")
        case .notInBible:
            problem = String(localized: "That passage isn't in the Bible you're reading.")
        case let .found(passage):
            problem = nil
            text = ""
            StudyStore(context: modelContext).attach(passage, to: sermon)
        }
    }
}

/// A passage's reference and words, verbatim from the current Bible.
struct SermonPassageText: View {
    let passage: PrayerPassage

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        let translation = library.currentTranslation
        let verses = (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("\(passage.reference.description(in: translation.language)) · \(translation.abbreviation)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.accent)
            if verses.isEmpty {
                Text("This passage isn't in the Bible you're reading.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text(verses.map(\.plainText).joined(separator: " "))
                    .font(settings.preferences.font.font(size: 16))
                    .foregroundStyle(palette.text)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Reads a typed reference against the Bible being read.
enum SermonPassageResolver {
    static func resolve(_ text: String, in repository: BibleRepository) -> SermonLookup.Outcome {
        SermonLookup.resolve(
            text,
            lastVerse: { chapter in (try? repository.chapter(chapter))?.verses.last?.id.verse },
            hasVerses: { passage in !((try? repository.verses(from: passage.start, through: passage.end)) ?? []).isEmpty }
        )
    }
}
