import Foundation

/// The Original view's word-by-word glosses in Spanish and Portuguese, read
/// from the bundled Glosses.sqlite (VRS-6; built by
/// Tools/StudyData/add_gloss_translations.py from the batches checked by
/// Tools/StudyData/glosses.py). They're Versely's translation of
/// STEPBible's English glosses (TAHOT, TAGNT; CC BY 4.0), one per Strong's
/// number, morphology and English gloss, so "your" follows the word's
/// grammar. A word without one keeps its English gloss.
final class OriginalGlosses: Sendable {
    /// Shown where translated glosses appear.
    static let translatedNote = String(localized: "Word meanings translated from STEPBible's English glosses. Not Scripture.")

    /// The credit CC BY 4.0 asks for, with what was changed
    /// (Tools/StudyData/translations/glosses/SOURCES.md).
    static let attribution = String(localized: "Spanish and Portuguese word meanings: an AI-assisted translation by Versely of the English glosses in STEPBible's TAHOT and TAGNT, data by Tyndale House Cambridge and STEPBible.org (STEPBible.github.io/STEPBible-Data), CC BY 4.0. Not reviewed or endorsed by STEPBible.")

    /// Languages the file may hold; only these reach the SQL below.
    static let languages: Set<String> = ["es", "pt"]

    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    /// The bundled file, opened once; nil if it's missing from the build.
    static let bundled: OriginalGlosses? = Bundle.main.url(forResource: "Glosses", withExtension: "sqlite").flatMap { try? OriginalGlosses(url: $0) }

    /// Shown with a gloss whose meaning is uncertain and still awaits a
    /// qualified reviewer (`OriginalWord.awaitsReview`).
    static let awaitingReviewNote = String(localized: "This meaning is uncertain and awaits review by a qualified reviewer.")

    /// The words with their glosses in `language` where the file has them
    /// (`englishGloss` keeps STEPBible's); the others are left as they are.
    /// A verse that needs another word than the gloss's usual one has its
    /// own (occurrence_glosses, by verse and position).
    func translated(_ words: [OriginalWord], into language: String) throws -> [OriginalWord] {
        guard Self.languages.contains(language), !words.isEmpty else { return words }
        let keys = Array(Set(words.map(Self.key)))
        var found: [Int: (text: String, awaits: Bool)] = [:]
        // A chapter can hold a few thousand words; keep each query's arguments modest.
        for start in stride(from: 0, to: keys.count, by: 500) {
            let chunk = keys[start..<min(start + 500, keys.count)]
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.query(
                "SELECT key, \(language), COALESCE(awaiting, '') FROM glosses WHERE key IN (\(marks)) AND \(language) IS NOT NULL",
                chunk.map { .int($0) }
            ) { (key: $0.int(0), text: $0.text(1), awaiting: $0.text(2)) }
            for row in rows {
                found[row.key] = (row.text, row.awaiting.split(separator: " ").contains(Substring(language)))
            }
        }
        let verses = words.map(\.verse.rawValue)
        var own: [String: String] = [:]
        if let low = verses.min(), let high = verses.max() {
            let rows = try database.query(
                "SELECT verse, position, key, \(language) FROM occurrence_glosses WHERE verse BETWEEN ? AND ? AND \(language) IS NOT NULL",
                [.int(low), .int(high)]
            ) { (place: "\($0.int(0)).\($0.int(1)).\($0.int(2))", text: $0.text(3)) }
            for row in rows { own[row.place] = row.text }
        }
        guard !found.isEmpty else { return words }
        return words.map { word in
            let key = Self.key(word)
            guard let usual = found[key] else { return word }
            var word = word
            word.englishGloss = word.gloss
            word.gloss = own["\(word.verse.rawValue).\(word.position).\(key)"] ?? usual.text
            word.awaitsReview = usual.awaits
            return word
        }
    }

    /// FNV-1a (64-bit) over the UTF-8 of "strongs␟morphology␟gloss", as a
    /// signed integer: the same as glosses.gloss_key in the build script.
    static func key(_ word: OriginalWord) -> Int {
        key(strongs: word.strongs ?? "", morphology: word.morphology, gloss: word.englishGloss ?? word.gloss)
    }

    static func key(strongs: String, morphology: String, gloss: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(strongs)\u{1F}\(morphology)\u{1F}\(gloss)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(Int64(bitPattern: hash))
    }
}

extension WordStudyRepository {
    /// The words with their glosses in `glossLanguage` ("es", "pt") when
    /// the bundled Glosses.sqlite has them; STEPBible's English otherwise.
    /// The gloss language is the reader's (`GlossLanguage`), never the
    /// app's.
    func withTranslatedGlosses(_ words: [OriginalWord], into glossLanguage: String, glosses: OriginalGlosses? = .bundled) -> [OriginalWord] {
        guard OriginalGlosses.languages.contains(glossLanguage), let glosses else { return words }
        return (try? glosses.translated(words, into: glossLanguage)) ?? words
    }
}
