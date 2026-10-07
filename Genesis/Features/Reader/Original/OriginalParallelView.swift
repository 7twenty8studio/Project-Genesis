import SwiftUI

/// The Bible being read beside the text it was translated from, verse by
/// verse: the Hebrew Old Testament (Leningrad Codex) and the Greek New
/// Testament in the edition that Bible follows (`OriginalSource`: the
/// Textus Receptus for the KJV, the Byzantine text for the WEB, …), word by
/// word from WordStudy.sqlite (Premium, `.wordStudy`; free accounts see the
/// first verses of each chapter).
///
/// Verses line up through `OriginalVersification`, so a verse the word data
/// numbers differently still meets its own Hebrew or Greek; a verse with
/// none shows none. Words are shown exactly as stored, and any word can be
/// tapped for its meaning (`OriginalWordSheet`). Interlinear puts each
/// word's transliteration and gloss beneath it.
struct OriginalParallelView: View {
    let chapterID: ChapterID
    let translation: Translation
    let map: VersificationMap
    /// The Greek edition this Bible was translated from (or the closest).
    let greek: OriginalSource.Greek
    let wordStudy: WordStudyRepository
    /// Space at the top for the floating reader controls.
    let topInset: CGFloat
    let bottomInset: CGFloat

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderViewModel.self) private var reader
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @AppStorage("reader.original.interlinear") private var interlinear = false
    /// Only the Hebrew or Greek, without the translation beside it.
    @AppStorage("reader.original.only") private var originalOnly = false

    @State private var rows: [OriginalParallelRow] = []
    @State private var picked: OriginalWord?

    private var unlocked: Bool { entitlements.allows(.wordStudy) }
    private var language: OriginalLanguage { chapterID.book >= 40 ? .greek : .hebrew }

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = proxy.size.width >= 600
            ScrollView {
                LazyVStack(alignment: .leading, spacing: sideBySide ? 16 : 20) {
                    OriginalParallelHeader(
                        chapterID: chapterID,
                        translation: translation,
                        language: language,
                        greek: greek,
                        sideBySide: sideBySide,
                        marksEditions: rows.contains { row in row.words.contains(where: \.isNotInComparison) },
                        interlinear: $interlinear,
                        originalOnly: $originalOnly
                    )
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        OriginalVerseRow(
                            row: row,
                            translation: translation,
                            language: language,
                            sideBySide: sideBySide,
                            interlinear: interlinear,
                            originalOnly: originalOnly,
                            onWord: { picked = $0 }
                        )
                        .modifier(PlayingVerseMark(isPlaying: row.verse == reader.playingVerse))
                        .id(row.number)
                        if !unlocked && index == OriginalParallel.previewVerses - 1 {
                            PremiumTeaser(message: String(localized: "Read the Hebrew and Greek beside every verse, word by word, with Premium."), feature: .wordStudy)
                        }
                    }
                    footer
                }
                .scrollTargetLayout()
                .padding(.horizontal, sideBySide ? 32 : 22)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset + 40)
                .frame(maxWidth: sideBySide ? 1100 : 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .modifier(ParallelFollowAlong(playingRow: playingRow, rowCount: rows.count))
            .contentShape(Rectangle())
            .onTapGesture { reader.toggleControls() }
        }
        .background(palette.background)
        .task(id: "\(chapterID.book)-\(chapterID.chapter)-\(translation.id)-\(greek.edition.rawValue)-\(unlocked)") { await load() }
        .sheet(item: $picked) { word in
            OriginalWordSheet(word: word)
        }
    }

    /// The verse being read aloud in this chapter (follow-along on).
    private var playingRow: Int? {
        guard let playing = reader.playingVerse, playing.chapterID == chapterID else { return nil }
        return rows.first { $0.verse == playing }?.number
    }

    private var footer: some View {
        VStack(spacing: 20) {
            if let next = chapterID.next {
                Button {
                    reader.open(next)
                } label: {
                    Label(next.description(in: translation.language), systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityIdentifier("parallel.next")
            }
            Text(WordStudyRepository.attribution)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func load() async {
        let bible = library.repository(for: translation)
        let chapter = chapterID
        let map = map
        let wordStudy = wordStudy
        let edition = greek.edition
        let limit = unlocked ? nil : OriginalParallel.previewVerses
        rows = await Task.detached(priority: .userInitiated) {
            let verses = (try? bible.chapter(chapter))?.verses ?? []
            let needed = OriginalParallel.kjvVerses(for: verses.map(\.id), map: map)
            let words = (try? wordStudy.words(inVerses: needed, greek: edition)) ?? [:]
            return OriginalParallel.rows(verses: verses, map: map, words: words, limit: limit)
        }.value
        // Keep the verse being read (so leaving parallel returns to it).
        let focus = reader.focusVerse.chapterID == chapterID ? reader.focusVerse : nil
        reader.didShow(chapter: chapterID, firstVerse: focus)
    }
}
