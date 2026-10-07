import SwiftUI

/// A verse's Hebrew or Greek, every word verbatim and tappable: as running
/// text (joined as `OriginalText` describes), or interlinear, each word with
/// its transliteration and gloss beneath. Hebrew reads right to left and
/// sits against the right edge. Greek words the compared edition doesn't
/// have (`OriginalWord.isNotInComparison`) get a dotted underline.
struct OriginalVerseView: View {
    let words: [OriginalWord]
    let language: OriginalLanguage
    /// Set when the original covers more than one verse of the Bible read.
    let reference: String?
    let interlinear: Bool
    /// The reader's text size; the original is set a little larger.
    let fontSize: CGFloat
    let onWord: @MainActor (OriginalWord) -> Void

    @Environment(\.palette) private var palette

    private static let scheme = "genesis-original"
    private var rightToLeft: Bool { language.isRightToLeft }
    private var alignment: Alignment { rightToLeft ? .trailing : .leading }

    var body: some View {
        VStack(alignment: rightToLeft ? .trailing : .leading, spacing: 6) {
            if let reference {
                Text(reference)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            if interlinear {
                InterlinearFlow(rightToLeft: rightToLeft, spacing: 12) {
                    ForEach(words) { word in
                        Button { onWord(word) } label: {
                            InterlinearWordView(word: word, fontSize: fontSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("original.word")
                    }
                }
            } else {
                runningText
            }
        }
        // Placement is worked out here, not mirrored by the system.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    /// The verse as one text; each word is a link that opens it.
    private var runningText: some View {
        Text(attributed)
            .font(OriginalFont.font(for: language, size: OriginalFont.readingSize(fontSize, language: language)))
            .foregroundStyle(palette.text)
            .tint(palette.text)
            .multilineTextAlignment(rightToLeft ? .trailing : .leading)
            .lineSpacing(fontSize * 0.35)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { [words, onWord] url in
                // SwiftUI opens links on the main thread.
                MainActor.assumeIsolated {
                    if let index = Self.index(from: url), words.indices.contains(index) {
                        onWord(words[index])
                    }
                }
                return .handled
            })
            .accessibilityIdentifier("original.text")
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, segment) in OriginalText.segments(words.map(\.text)).enumerated() {
            var word = AttributedString(segment.text)
            word.link = URL(string: "\(Self.scheme)://\(index)")
            if words[index].isNotInComparison {
                word.underlineStyle = Text.LineStyle(pattern: .dot, color: palette.accent)
            }
            result += word
            result += AttributedString(segment.separator)
        }
        return result
    }

    private static func index(from url: URL) -> Int? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        return Int(host)
    }
}

/// Typefaces for the original languages: Noto Serif Hebrew (every vowel
/// point and cantillation mark) and EB Garamond (polytonic Greek), both
/// bundled under the SIL Open Font License.
enum OriginalFont {
    static func font(for language: OriginalLanguage, size: CGFloat) -> Font {
        switch language {
        case .hebrew: .custom("NotoSerifHebrew-Regular", fixedSize: size)
        case .greek: .custom("EBGaramond-Regular", fixedSize: size)
        }
    }

    /// Pointed Hebrew needs more size than English to read comfortably.
    static func readingSize(_ size: CGFloat, language: OriginalLanguage) -> CGFloat {
        language == .hebrew ? size * 1.3 : size * 1.08
    }
}
