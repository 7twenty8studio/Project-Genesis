import Foundation
import SQLite3

/// Writes a Bible database in the app's format: the same tables as
/// Tools/BibleData/build_bibles.py (`create_bible_db`), so BibleRepository
/// reads it like a bundled or downloaded Bible. Used for YouVersion Platform
/// Bibles, which are built on the device. The verse text is written exactly
/// as given; only the search index holds a search-friendly form.
enum BibleFileWriter {
    enum Failure: Error, CustomStringConvertible {
        case sqlite(String)

        var description: String {
            switch self {
            case let .sqlite(message): "Could not write the Bible: \(message)"
            }
        }
    }

    /// Same as build_bibles.py's SCHEMA_VERSION.
    static let schemaVersion = 1

    static func write(books: [Int: YouVersionBook], translation: Translation, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path(percentEncoded: false), &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw Failure.sqlite("open")
        }
        // close_v2 waits for any statement still open (after an error).
        defer { sqlite3_close_v2(db) }

        // The Porter stemmer is English-only ("loving" finds "love"); other
        // languages are matched by whole words and prefixes, accents ignored.
        let tokenizer = translation.language.hasPrefix("en") ? "porter unicode61 remove_diacritics 2" : "unicode61 remove_diacritics 2"
        try execute(db, """
            PRAGMA page_size = 4096;
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE books (
                id INTEGER PRIMARY KEY,
                osis TEXT NOT NULL,
                name TEXT NOT NULL,
                testament TEXT NOT NULL,
                chapter_count INTEGER NOT NULL
            );
            CREATE TABLE verses (
                id INTEGER PRIMARY KEY,
                book INTEGER NOT NULL,
                chapter INTEGER NOT NULL,
                verse INTEGER NOT NULL,
                text TEXT NOT NULL,
                paragraph INTEGER NOT NULL DEFAULT 0,
                poetry INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE headings (
                book INTEGER NOT NULL,
                chapter INTEGER NOT NULL,
                before_verse INTEGER NOT NULL,
                text TEXT NOT NULL
            );
            CREATE INDEX headings_chapter ON headings(book, chapter);
            CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='', tokenize='\(tokenizer)', prefix='2 3 4');
            BEGIN;
            """)

        let meta = try Statement(db, "INSERT INTO meta VALUES (?, ?)")
        for (key, value) in [
            ("abbreviation", translation.abbreviation),
            ("name", translation.name),
            ("year", translation.year),
            ("license", translation.license),
            ("language", translation.language),
            ("schema_version", String(schemaVersion)),
        ] {
            try meta.run([.text(key), .text(value)])
        }
        meta.finish()

        let book = try Statement(db, "INSERT INTO books VALUES (?, ?, ?, ?, ?)")
        for info in BibleBook.all {
            let chapters = books[info.id]?.chapters.map(\.chapter).max() ?? info.chapterCount
            try book.run([.int(info.id), .text(info.osis), .text(info.englishName), .text(info.testament.rawValue), .int(chapters)])
        }
        book.finish()

        // Like build_bibles.py, the joined-verse table exists only when the
        // Bible joins verses (BibleRepository then looks them up).
        let joinsVerses = books.values.contains { book in
            book.chapters.contains { chapter in chapter.verses.contains { ($0.last ?? 0) > $0.verse } }
        }
        if joinsVerses {
            try execute(db, "CREATE TABLE verse_spans (id INTEGER PRIMARY KEY, last INTEGER NOT NULL);")
        }
        let verse = try Statement(db, "INSERT INTO verses VALUES (?, ?, ?, ?, ?, ?, ?)")
        let heading = try Statement(db, "INSERT INTO headings VALUES (?, ?, ?, ?)")
        let span: Statement? = try (joinsVerses ? Statement(db, "INSERT INTO verse_spans VALUES (?, ?)") : nil)
        let search = try Statement(db, "INSERT INTO verses_fts(rowid, text) VALUES (?, ?)")
        for number in books.keys.sorted() {
            guard let content = books[number] else { continue }
            for chapter in content.chapters {
                var seen = Set<Int>()
                for item in chapter.verses where !item.text.isEmpty && seen.insert(item.verse).inserted {
                    let id = VerseID(book: number, chapter: chapter.chapter, verse: item.verse).rawValue
                    try verse.run([.int(id), .int(number), .int(chapter.chapter), .int(item.verse), .text(item.text), .int(item.paragraph ? 1 : 0), .int(item.poetry ? 1 : 0)])
                    try search.run([.int(id), .text(BibleSearchForm.indexed(item.text))])
                    if let span, let last = item.last, last > item.verse {
                        try span.run([.int(id), .int(VerseID(book: number, chapter: chapter.chapter, verse: last).rawValue)])
                    }
                }
                for item in chapter.headings where seen.contains(item.beforeVerse) {
                    try heading.run([.int(number), .int(chapter.chapter), .int(item.beforeVerse), .text(item.text)])
                }
            }
        }
        verse.finish()
        heading.finish()
        span?.finish()
        search.finish()
        try execute(db, "COMMIT; INSERT INTO verses_fts(verses_fts) VALUES ('optimize');")
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "exec"
            sqlite3_free(message)
            throw Failure.sqlite(text)
        }
    }

    /// A prepared insert, run once per row.
    private final class Statement {
        enum Value {
            case int(Int)
            case text(String)
        }

        private let db: OpaquePointer
        private var statement: OpaquePointer?

        init(_ db: OpaquePointer, _ sql: String) throws {
            self.db = db
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
                throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }

        deinit { finish() }

        func run(_ values: [Value]) throws {
            guard let statement else { throw Failure.sqlite("finished statement") }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (index, value) in values.enumerated() {
                let position = Int32(index + 1)
                switch value {
                case let .int(number):
                    sqlite3_bind_int64(statement, position, sqlite3_int64(number))
                case let .text(text):
                    sqlite3_bind_text(statement, position, text, -1, BibleFileWriter.transient)
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }

        func finish() {
            if let statement { sqlite3_finalize(statement) }
            statement = nil
        }
    }

    /// SQLite copies bound strings, since Swift may free them before the step.
    fileprivate static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}

/// The form of a verse kept in the search index, never shown: the same rule
/// as build_bibles.py's `search_form`. Hyphenated names such as
/// "Beth–lehem" are indexed both joined ("Bethlehem") and as written, so
/// either spelling finds them.
enum BibleSearchForm {
    private static let hyphens = "\u{2010}\u{2011}\u{2013}-"
    // \w+(?:[hyphens]\w+)+
    nonisolated(unsafe) private static let hyphenated = try! NSRegularExpression(pattern: "\\w+(?:[\u{2010}\u{2011}\u{2013}\\-]\\w+)+")

    static func indexed(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let matches = hyphenated.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let wordRange = Range(match.range, in: result) else { continue }
            let word = String(result[wordRange])
            let joined = word.filter { !hyphens.contains($0) }
            result.replaceSubrange(wordRange, with: word + " " + joined)
        }
        return result
    }
}
