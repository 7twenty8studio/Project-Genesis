import Foundation

/// Parses typed Bible references such as "John 3:16", "jn 3", "1 Cor 13:4-7",
/// "I John 1:9", "Ps 23" or "Song of Songs 2", and the Spanish names
/// ("Juan 3:16", "1 Corintios 13", "Sal 23", "Génesis" or "genesis") whatever
/// the app's language.
enum ReferenceParser {
    /// Parses a complete reference. Returns nil if the text isn't a reference.
    static func parse(_ input: String) -> PassageReference? {
        let text = normalize(input)
        guard !text.isEmpty else { return nil }

        let (bookText, numberText) = split(text)
        guard let book = book(named: bookText) else { return nil }

        let numbers = parseNumbers(numberText)
        guard numbers.isValid else { return nil }

        guard let first = numbers.chapter else {
            return PassageReference(book: book)
        }

        // Single-chapter books are cited by verse: "Jude 3" means verse 3.
        if book.chapterCount == 1, numbers.verse == nil, first > 1 {
            return PassageReference(book: book, chapter: 1, verseStart: first, verseEnd: numbers.verseEnd)
        }

        guard (1...book.chapterCount).contains(first) else { return nil }
        if let verse = numbers.verse, verse < 1 { return nil }
        if let verse = numbers.verse, let end = numbers.verseEnd, end < verse { return nil }
        return PassageReference(book: book, chapter: first, verseStart: numbers.verse, verseEnd: numbers.verseEnd)
    }

    /// Books whose name or abbreviation starts with the typed text. Used for
    /// suggestions while the user is still typing a book name.
    static func books(matching input: String) -> [BibleBook] {
        let (bookText, numberText) = split(normalize(input))
        guard !bookText.isEmpty, numberText.isEmpty else { return [] }
        let key = compact(bookText)
        if let exact = index[key] { return [exact] }
        return BibleBook.all.filter { book in (keys(for: book) + spanishKeys(for: book)).contains { $0.hasPrefix(key) } }
    }

    /// Resolves a book from any accepted spelling.
    static func book(named text: String) -> BibleBook? {
        let key = compact(text)
        guard !key.isEmpty else { return nil }
        if let book = index[key] { return book }
        // Fall back to an unambiguous prefix of a book name ("gene", "phile").
        guard key.count >= 3 else { return nil }
        let matches = BibleBook.all.filter { book in
            [book.englishName, book.name(in: "es")].contains { compact($0).hasPrefix(key) }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    // MARK: - Internals

    private static let ordinals: [(prefix: String, digit: String)] = [
        ("first ", "1"), ("second ", "2"), ("third ", "3"),
        ("1st ", "1"), ("2nd ", "2"), ("3rd ", "3"),
        ("primera de ", "1"), ("segunda de ", "2"), ("tercera de ", "3"),
        ("primera ", "1"), ("primero ", "1"), ("segunda ", "2"), ("segundo ", "2"), ("tercera ", "3"), ("tercero ", "3"),
        ("1ra ", "1"), ("1ro ", "1"), ("2da ", "2"), ("2do ", "2"), ("3ra ", "3"), ("3ro ", "3"),
        ("iii ", "3"), ("ii ", "2"), ("i ", "1"),
    ]

    private static func normalize(_ input: String) -> String {
        var text = input.lowercased()
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for (prefix, digit) in ordinals where text.hasPrefix(prefix) {
            text = digit + String(text.dropFirst(prefix.count))
            break
        }
        return text
    }

    /// Splits "1 cor 13:4-7" into ("1 cor", "13:4-7"). A leading 1–3 belongs
    /// to the book name when letters follow it.
    private static func split(_ text: String) -> (book: String, numbers: String) {
        let characters = Array(text)
        var index = 0
        if let first = characters.first, "123".contains(first) {
            var lookahead = 1
            while lookahead < characters.count, characters[lookahead] == " " { lookahead += 1 }
            if lookahead < characters.count, characters[lookahead].isLetter { index = lookahead }
        }
        while index < characters.count, characters[index].isLetter || characters[index] == " " || characters[index] == "." {
            index += 1
        }
        let book = String(characters[..<index]).replacingOccurrences(of: ".", with: " ")
        let numbers = String(characters[index...])
        return (book.trimmingCharacters(in: .whitespaces), numbers.trimmingCharacters(in: .whitespaces))
    }

    private struct Numbers {
        var chapter: Int?
        var verse: Int?
        var verseEnd: Int?
        var isValid = true
    }

    /// Parses "3", "3:16", "3.16", "3 16", "3:16-18" or "3:16-4:2" (end chapter ignored).
    private static func parseNumbers(_ text: String) -> Numbers {
        var result = Numbers()
        guard !text.isEmpty else { return result }
        let characters = Array(text)
        var index = 0

        func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }

        func readNumber() -> Int? {
            let start = index
            while index < characters.count, characters[index].isNumber { index += 1 }
            return index > start ? Int(String(characters[start..<index])) : nil
        }

        guard let chapter = readNumber() else {
            result.isValid = false
            return result
        }
        result.chapter = chapter
        skipSpaces()

        if index < characters.count, [":", ".", ","].contains(characters[index]) {
            index += 1
            skipSpaces()
        }
        if index < characters.count, characters[index].isNumber {
            result.verse = readNumber()
            skipSpaces()
            if index < characters.count, characters[index] == "-" {
                index += 1
                skipSpaces()
                let end = readNumber()
                // "3:16-4:2": the number after "-" was a chapter; keep the start verse only.
                if index < characters.count, characters[index] == ":" {
                    index = characters.count
                } else {
                    result.verseEnd = end
                }
            }
        }

        skipSpaces()
        if index < characters.count { result.isValid = false }
        return result
    }

    /// Lowercase, without spaces, dots or accents: "1 Crónicas" → "1cronicas".
    private static func compact(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { !$0.isWhitespace && $0 != "." }
    }

    /// English spellings first, so an English abbreviation wins where the two
    /// languages share one ("Mc" is Micah, as in English).
    private static func keys(for book: BibleBook) -> [String] {
        ([book.englishName, book.englishAbbreviation, book.osis] + book.aliases).map(compact)
    }

    private static func spanishKeys(for book: BibleBook) -> [String] {
        ([book.name(in: "es"), book.abbreviation(in: "es")] + book.spanishAliases).map(compact)
    }

    private static let index: [String: BibleBook] = {
        var index: [String: BibleBook] = [:]
        for book in BibleBook.all {
            for key in keys(for: book) where index[key] == nil {
                index[key] = book
            }
        }
        for book in BibleBook.all {
            for key in spanishKeys(for: book) where index[key] == nil {
                index[key] = book
            }
        }
        return index
    }()
}
