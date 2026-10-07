import Foundation

/// Which KJV verses hold the same text as one or more verses of another
/// Bible. Usually one verse to one; where Bibles divide a passage
/// differently, a verse can hold two KJV verses (Acts 19:40 in the
/// Reina-Valera holds KJV 19:40–41), two verses can share one, or a verse
/// can have none (the WEB's empty Romans 16:25, whose words it prints at
/// 14:24–26).
struct VerseAlignment: Hashable, Sendable {
    /// In the Bible's own numbering, in order.
    let verses: [VerseID]
    /// The KJV verses with the same text, in order (empty: none).
    let kjv: [VerseID]
}

/// How one Bible's verse numbers line up with the KJV's, which
/// WordStudy.sqlite (the Hebrew and Greek) follows. Only the verses
/// numbered differently are listed; every other verse is the KJV verse with
/// the same number.
struct VersificationMap: Sendable {
    private let exceptions: [VerseID: VerseAlignment]
    /// KJV verses the exceptions hand to other verse numbers, so no verse
    /// with the same number takes them too.
    private let claimed: Set<VerseID>

    init(exceptions: [VerseAlignment]) {
        var table: [VerseID: VerseAlignment] = [:]
        for alignment in exceptions {
            for verse in alignment.verses {
                table[verse] = alignment
            }
        }
        self.exceptions = table
        claimed = Set(exceptions.flatMap(\.kjv))
    }

    /// The alignment a verse belongs to.
    func alignment(of verse: VerseID) -> VerseAlignment {
        if let exception = exceptions[verse] {
            return exception
        }
        return VerseAlignment(verses: [verse], kjv: claimed.contains(verse) ? [] : [verse])
    }

    /// The alignments covering a chapter's verses, in order, each once.
    func alignments(for verses: [VerseID]) -> [VerseAlignment] {
        var seen = Set<VerseAlignment>()
        return verses.map(alignment(of:)).filter { seen.insert($0).inserted }
    }

    static let kjv = VersificationMap(exceptions: [])
}

/// Lines up the Bibles the app reads with the KJV's verse numbers, for the
/// Original parallel Bible. Only Bibles whose numbering has been checked
/// verse by verse are listed: KJV and ASV share the KJV's numbering; the WEB
/// prints Romans 16:25–27 at 14:24–26; the Reina-Valera 1909 (Spanish
/// numbering) differs in 44 places, listed in VersificationTables.swift
/// (Tools/BibleData/align_versification.py). Other Bibles show no original
/// text rather than risk showing the wrong verse.
enum OriginalVersification {
    static func map(for translationID: String) -> VersificationMap? {
        switch translationID {
        case "KJV", "ASV": VersificationMap.kjv
        case "WEB": web
        case "RV1909": reinaValera1909
        default: nil
        }
    }

    static func supports(_ translation: Translation) -> Bool {
        map(for: translation.id) != nil
    }

    private static let web = VersificationMap(exceptions: webExceptions)
    private static let reinaValera1909 = VersificationMap(exceptions: reinaValera1909Exceptions)

    /// The WEB keeps the doxology (KJV Romans 16:25–27) at 14:24–26 and
    /// leaves 16:25 empty.
    static let webExceptions: [VerseAlignment] =
        shift(book: 45, chapter: 14, verses: 24...26, kjvChapter: 16, by: 1)
        + [VerseAlignment(verses: [VerseID(book: 45, chapter: 16, verse: 25)], kjv: [])]

    // MARK: Building tables

    /// Verses `verses` of a chapter hold the KJV verses `by` later (or
    /// earlier) in `kjvChapter`, one for one.
    static func shift(book: Int, chapter: Int, verses: ClosedRange<Int>, kjvChapter: Int, by offset: Int) -> [VerseAlignment] {
        verses.map { verse in
            VerseAlignment(
                verses: [VerseID(book: book, chapter: chapter, verse: verse)],
                kjv: [VerseID(book: book, chapter: kjvChapter, verse: verse + offset)]
            )
        }
    }

    /// Some verses (chapter, verse) holding some KJV verses, together.
    static func group(book: Int, _ verses: [(Int, Int)], kjv: [(Int, Int)]) -> [VerseAlignment] {
        [VerseAlignment(
            verses: verses.map { VerseID(book: book, chapter: $0.0, verse: $0.1) },
            kjv: kjv.map { VerseID(book: book, chapter: $0.0, verse: $0.1) }
        )]
    }
}
