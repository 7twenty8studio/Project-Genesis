import SwiftUI

/// Two Bibles side by side, verse by verse: the current translation and a
/// second one (KJV with WEB, or English with the Reina-Valera). Rows line up
/// by verse number, so where the two number a chapter differently a verse
/// simply has no partner on one side.
///
/// Wide screens (iPad, the open iPhone Duo) give each translation half the
/// screen, so on the Duo each sits on its own side of the hinge. On a phone
/// the second translation follows each verse, set a little smaller.
struct ParallelChapterView: View {
    let chapterID: ChapterID
    let primary: Translation
    let secondary: Translation
    /// Space at the top for the floating reader controls.
    let topInset: CGFloat
    let bottomInset: CGFloat

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderViewModel.self) private var reader
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    @State private var rows: [ParallelRow] = []

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = proxy.size.width >= 600
            ScrollView {
                LazyVStack(alignment: .leading, spacing: sideBySide ? 14 : 18) {
                    header(sideBySide: sideBySide)
                    ForEach(rows) { row in
                        Group {
                        if sideBySide {
                            HStack(alignment: .top, spacing: 0) {
                                verse(row.primary, number: row.number, emphasis: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.trailing, 24)
                                verse(row.secondary, number: row.number, emphasis: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 24)
                                    // The rule between the columns (on the Duo, along the hinge).
                                    .overlay(alignment: .leading) {
                                        Rectangle().fill(palette.separator).frame(width: 1)
                                    }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                verse(row.primary, number: row.number, emphasis: true)
                                if row.secondary != nil {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(secondary.abbreviation)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(palette.accent)
                                            .padding(.top, 3)
                                        verse(row.secondary, number: nil, emphasis: false)
                                    }
                                }
                            }
                        }
                        }
                        .modifier(PlayingVerseMark(isPlaying: row.number == playingRow))
                        .id(row.number)
                    }
                    nextChapterButton
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
        .task(id: "\(chapterID.book)-\(chapterID.chapter)-\(primary.id)-\(secondary.id)") { load() }
    }

    /// The verse being read aloud in this chapter (follow-along on).
    private var playingRow: Int? {
        guard let playing = reader.playingVerse, playing.chapterID == chapterID else { return nil }
        return playing.verse
    }

    private func header(sideBySide: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if sideBySide {
                column(title: primary).frame(maxWidth: .infinity, alignment: .leading)
                column(title: secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 25)
            } else {
                Text("\(primary.abbreviation) and \(secondary.abbreviation)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reader.parallel")
    }

    private func column(title translation: Translation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chapterID.description(in: translation.language))
                .font(settings.preferences.font.font(size: 22, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(translation.name)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ViewBuilder
    private func verse(_ text: String?, number: Int?, emphasis: Bool) -> some View {
        let size = CGFloat(settings.preferences.fontSize) * (emphasis ? 1 : 0.88)
        if let text {
            Text(numbered(text, number: number))
                .font(settings.preferences.font.font(size: size))
                .foregroundStyle(emphasis ? palette.text : palette.secondaryText)
                .lineSpacing(size * CGFloat(settings.preferences.lineSpacing - 1))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            // A verse number this translation doesn't use here.
            numberText(number)
                .font(settings.preferences.font.font(size: size))
                .accessibilityHidden(true)
        }
    }

    /// The verse with its small raised number, as one run of text (the
    /// verse's words are verbatim; only the number is styled).
    private func numbered(_ text: String, number: Int?) -> AttributedString {
        var result = AttributedString()
        if let number {
            var label = AttributedString("\(number) ")
            label.font = .system(size: 11, weight: .semibold)
            label.foregroundColor = palette.accent
            label.baselineOffset = 6
            result += label
        }
        result += AttributedString(text)
        return result
    }

    private func numberText(_ number: Int?) -> Text {
        guard let number else { return Text(verbatim: "") }
        return Text(verbatim: "\(number) ")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.accent)
            .baselineOffset(6)
    }

    private var nextChapterButton: some View {
        HStack {
            Spacer()
            if let next = chapterID.next {
                Button {
                    reader.open(next)
                } label: {
                    Label(next.description, systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityIdentifier("parallel.next")
            }
            Spacer()
        }
        .padding(.top, 20)
    }

    private func load() {
        let first = (try? library.repository(for: primary).chapter(chapterID))?.verses ?? []
        let second = (try? library.repository(for: secondary).chapter(chapterID))?.verses ?? []
        rows = ParallelRow.merge(first, second)
        // Keep the verse being read (so leaving parallel returns to it).
        let focus = reader.focusVerse.chapterID == chapterID ? reader.focusVerse : nil
        reader.didShow(chapter: chapterID, firstVerse: focus)
    }
}

/// One verse number with its text in each translation (nil where a
/// translation has no verse with that number in this chapter).
struct ParallelRow: Identifiable, Equatable, Sendable {
    let number: Int
    let primary: String?
    let secondary: String?
    var id: Int { number }

    /// Pairs verses by number; a number only one side uses gets an empty partner.
    static func merge(_ first: [Verse], _ second: [Verse]) -> [ParallelRow] {
        let firstByNumber = Dictionary(first.map { ($0.id.verse, $0.plainText) }, uniquingKeysWith: { a, _ in a })
        let secondByNumber = Dictionary(second.map { ($0.id.verse, $0.plainText) }, uniquingKeysWith: { a, _ in a })
        return Set(firstByNumber.keys).union(secondByNumber.keys).sorted().map { number in
            ParallelRow(number: number, primary: firstByNumber[number], secondary: secondByNumber[number])
        }
    }
}


