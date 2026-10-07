import Foundation

/// Hebrew and Greek verse text put together from WordStudy.sqlite's words,
/// as the source writes it. Every word is kept exactly as stored, with its
/// vowel points, accents and punctuation (sof pasuq ׃, Greek commas and
/// stops); only the space between words is chosen here:
/// - a word ending in maqaf (־) is joined to the next word with no space,
///   since the maqaf binds the two;
/// - a paseq (׀), which the source attaches to the word before it, is set
///   apart by a space, as printed Hebrew Bibles show it;
/// - otherwise one space.
enum OriginalText {
    static let maqaf: Unicode.Scalar = "\u{05BE}"
    static let paseq: Unicode.Scalar = "\u{05C0}"

    /// One word as shown, and what follows it before the next word.
    struct Segment: Hashable, Sendable {
        /// The word, verbatim (a trailing paseq set apart by a space).
        let text: String
        /// "" after a maqaf, an empty word or the last word, " " otherwise.
        let separator: String
    }

    static func segments(_ words: [String]) -> [Segment] {
        words.enumerated().map { index, word in
            let last = index == words.count - 1
            // An empty word (a Ketiv the reading leaves out) adds no space.
            let joined = word.isEmpty || word.unicodeScalars.last == maqaf
            return Segment(text: display(word), separator: last || joined ? "" : " ")
        }
    }

    /// The words joined into one line of text.
    static func joined(_ words: [String]) -> String {
        segments(words).map { $0.text + $0.separator }.joined()
    }

    /// A word as shown: verbatim, except that a paseq at its end stands apart.
    static func display(_ word: String) -> String {
        var scalars = word.unicodeScalars
        guard scalars.count > 1, scalars.last == paseq else { return word }
        scalars.removeLast()
        var text = String(scalars)
        guard text.unicodeScalars.last != " " else { return word }
        text.append(" ")
        text.unicodeScalars.append(paseq)
        return text
    }
}

/// One row of the Original parallel Bible: a verse of the Bible being read,
/// verbatim, beside the Hebrew or Greek of the KJV verses it holds.
struct OriginalParallelRow: Identifiable, Hashable, Sendable {
    /// The verse in the Bible being read.
    let verse: VerseID
    /// Its text, verbatim.
    let text: String
    /// The Hebrew or Greek words, in order. Empty when there are none, when
    /// they're shown with an earlier verse (`isContinuation`), or in a
    /// preview.
    let words: [OriginalWord]
    /// Where the original covers more than this verse (verses divided
    /// differently), the verse numbers it covers, e.g. 25...26.
    let covers: ClosedRange<Int>?
    /// The original for this verse was shown with an earlier one.
    let isContinuation: Bool

    var id: VerseID { verse }
    var number: Int { verse.verse }
}

/// Builds the rows of the Original parallel Bible for one chapter.
enum OriginalParallel {
    /// Free accounts see the original of this many verses of each chapter.
    static let previewVerses = 2

    /// Every KJV verse whose words a chapter needs.
    static func kjvVerses(for verses: [VerseID], map: VersificationMap) -> [VerseID] {
        map.alignments(for: verses).flatMap(\.kjv)
    }

    /// Rows for the chapter's verses (`verses`, in order, verbatim), with
    /// the words of each verse's KJV verses (`words`, keyed by KJV verse).
    /// `limit` keeps the original to the first few verses (a preview).
    static func rows(
        verses: [Verse],
        map: VersificationMap,
        words: [VerseID: [OriginalWord]],
        limit: Int? = nil
    ) -> [OriginalParallelRow] {
        let present = Set(verses.map(\.id))
        return verses.enumerated().map { index, verse -> OriginalParallelRow in
            let alignment = map.alignment(of: verse.id)
            // A group's words go with its first verse in this chapter.
            let first = alignment.verses.first { present.contains($0) } ?? verse.id
            let isContinuation = first != verse.id
            let shown = limit.map { index < $0 } ?? true
            let original: [OriginalWord] = isContinuation || !shown ? [] : alignment.kjv.flatMap { words[$0] ?? [] }
            let numbers = alignment.verses.filter { $0.chapterID == verse.id.chapterID }.map(\.verse)
            var covers: ClosedRange<Int>?
            if numbers.count > 1, let low = numbers.min(), let high = numbers.max() {
                covers = low...high
            }
            return OriginalParallelRow(
                verse: verse.id,
                text: verse.plainText,
                words: original,
                covers: covers,
                isContinuation: isContinuation
            )
        }
    }
}
