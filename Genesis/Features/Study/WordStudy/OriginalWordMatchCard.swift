import SwiftUI

/// One Hebrew or Greek word matched to the picked English: how sure the
/// match is, the word verbatim, its transliteration, Strong's number, gloss
/// in this verse, part of speech, the lexicon's definition and how often it's
/// used.
struct OriginalWordMatchCard: View {
    let match: OriginalWordMatch
    let entry: LexiconEntry?
    let usageCount: Int

    @Environment(\.palette) private var palette

    private var word: OriginalWord { match.word }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            confidence
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.text)
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                if let strongs = word.strongs {
                    Text(strongs)
                        .font(.caption.monospaced())
                        .foregroundStyle(palette.accent)
                }
            }
            Text(word.transliteration)
                .font(.subheadline.italic())
                .foregroundStyle(palette.secondaryText)
            Text("In this verse: \(word.gloss)")
                .font(.subheadline)
                .foregroundStyle(palette.text)
            if let part = PartOfSpeech(morphology: word.morphology, language: word.language) {
                Text(part.title)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            if let entry, !entry.definition.isEmpty {
                Text(entry.definition)
                    .font(.callout)
                    .foregroundStyle(palette.text)
                    .lineLimit(6)
            }
            usage
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("originalWord.match")
    }

    private var confidence: some View {
        Label(
            match.isLikely ? String(localized: "Likely") : String(localized: "Closest match"),
            systemImage: match.isLikely ? "checkmark.seal" : "questionmark.circle"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(match.isLikely ? palette.accent : palette.secondaryText)
    }

    @ViewBuilder
    private var usage: some View {
        if usageCount == 1 {
            Text("Used once in the Bible.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        } else if usageCount > 1 {
            Text("Used \(usageCount) times in the Bible.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }
}
