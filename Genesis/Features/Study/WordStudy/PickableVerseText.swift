import SwiftUI

/// A verse, verbatim, whose words can be tapped to pick them. Picked words
/// are marked with a background; the text itself is never changed.
struct PickableVerseText: View {
    let text: String
    /// The verse's words (`VerseWords.ranges`).
    let words: [Range<String.Index>]
    let picked: Set<Int>
    let onToggle: (Int) -> Void

    @Environment(\.palette) private var palette

    private static let scheme = "genesis-word"

    var body: some View {
        Text(attributed)
            .font(.system(.title3, design: .serif))
            .foregroundStyle(palette.text)
            .tint(palette.text)
            .lineSpacing(4)
            .environment(\.openURL, OpenURLAction { url in
                if let index = Self.index(from: url) { onToggle(index) }
                return .handled
            })
            .accessibilityIdentifier("originalWord.verse")
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for (index, range) in words.enumerated() where range.lowerBound >= cursor {
            result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            var word = AttributedString(String(text[range]))
            word.link = URL(string: "\(Self.scheme)://\(index)")
            if picked.contains(index) {
                word.backgroundColor = palette.accent.opacity(0.28)
            }
            result.append(word)
            cursor = range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    private static func index(from url: URL) -> Int? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        return Int(host)
    }
}
