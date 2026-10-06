import SwiftUI

/// Book and chapter navigation.
struct ChapterPickerView: View {
    let onSelect: (ChapterID) -> Void

    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var testament: Testament = .old
    @State private var filter = ""
    @State private var path: [BibleBook] = []

    /// Book names follow the Bible being read ("Marcos" in a Spanish Bible).
    private var language: String { reader.translation.language }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ThemedRows {
                    if filter.isEmpty {
                        Picker("Testament", selection: $testament) {
                            ForEach(Testament.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }

                    ForEach(books) { book in
                        Button {
                            if book.chapterCount == 1 {
                                onSelect(ChapterID(book: book.id, chapter: 1))
                            } else {
                                path.append(book)
                            }
                        } label: {
                            HStack {
                                Text(book.name(in: language))
                                    .foregroundStyle(palette.text)
                                Spacer()
                                if book.id == reader.chapterID.book {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundStyle(palette.accent)
                                        .accessibilityLabel("Currently reading")
                                }
                                Text("\(book.chapterCount)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: BibleBook.self) { book in
                ChapterGrid(book: book, current: reader.chapterID, language: language, onSelect: onSelect)
            }
            .onAppear {
                testament = reader.chapterID.bibleBook.testament
            }
        }
    }

    private var books: [BibleBook] {
        guard !filter.isEmpty else {
            return testament == .old ? BibleBook.oldTestament : BibleBook.newTestament
        }
        let matches = ReferenceParser.books(matching: filter)
        return matches.isEmpty ? BibleBook.all.filter { $0.name(in: language).localizedCaseInsensitiveContains(filter) || $0.name.localizedCaseInsensitiveContains(filter) } : matches
    }
}

private struct ChapterGrid: View {
    let book: BibleBook
    let current: ChapterID
    let language: String
    let onSelect: (ChapterID) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                ForEach(1...book.chapterCount, id: \.self) { number in
                    let isCurrent = current == ChapterID(book: book.id, chapter: number)
                    Button {
                        onSelect(ChapterID(book: book.id, chapter: number))
                    } label: {
                        Text("\(number)")
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(isCurrent ? palette.background : palette.text)
                            .background(isCurrent ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("Chapter \(number)")
                }
            }
            .padding(20)
        }
        .themedScreen()
        .navigationTitle(book.name(in: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
