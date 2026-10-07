import SwiftUI

/// One verse of the Bible being read beside its Hebrew or Greek: side by
/// side on wide screens (on the open iPhone Duo, one each side of the
/// hinge), the original beneath the verse on a phone.
struct OriginalVerseRow: View {
    let row: OriginalParallelRow
    let translation: Translation
    let language: OriginalLanguage
    let sideBySide: Bool
    let interlinear: Bool
    /// Only the Hebrew or Greek, with the verse number (no translation).
    var originalOnly = false
    let onWord: @MainActor (OriginalWord) -> Void

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        if originalOnly {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(row.number)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                original
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .contain)
        } else if sideBySide {
            HStack(alignment: .top, spacing: 0) {
                verse
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 24)
                original
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 24)
                    // The rule between the columns (on the Duo, along the hinge).
                    .overlay(alignment: .leading) {
                        Rectangle().fill(palette.separator).frame(width: 1)
                    }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                verse
                original
            }
        }
    }

    private var fontSize: CGFloat { CGFloat(settings.preferences.fontSize) }

    /// The verse with its small raised number; the words are verbatim.
    private var verse: some View {
        Text(numbered)
            .font(settings.preferences.font.font(size: fontSize))
            .foregroundStyle(palette.text)
            .lineSpacing(fontSize * CGFloat(settings.preferences.lineSpacing - 1))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var numbered: AttributedString {
        var label = AttributedString("\(row.number) ")
        label.font = .system(size: 11, weight: .semibold)
        label.foregroundColor = palette.accent
        label.baselineOffset = 6
        var result = label
        result += AttributedString(row.text)
        return result
    }

    @ViewBuilder
    private var original: some View {
        if !row.words.isEmpty {
            OriginalVerseView(
                words: row.words,
                language: language,
                reference: coveredReference,
                interlinear: interlinear,
                fontSize: fontSize,
                onWord: onWord
            )
        }
    }

    /// "1 Samuel 10:25–26" when the original covers more than this verse.
    private var coveredReference: String? {
        guard let covers = row.covers else { return nil }
        return PassageReference(
            book: .withNumber(row.verse.book),
            chapter: row.verse.chapter,
            verseStart: covers.lowerBound,
            verseEnd: covers.upperBound
        ).description(in: translation.language)
    }
}
