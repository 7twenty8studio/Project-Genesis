import Foundation
import SQLite3

/// Writes a Bible database in the app's format: the same tables as
/// Tools/BibleData/build_bibles.py (`create_bible_db`), so BibleRepository
/// reads it like a bundled or downloaded Bible, plus `footnotes` (verse id,
/// position in the verse's text, the note) when the source has them. Used
/// for YouVersion Platform Bibles, which are built on the device: in memory,
/// so the licensed text only reaches the disk sealed (`BibleProtection`).
/// The verse text is written exactly as given; only the search index holds
/// a search-friendly form.
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

    /// The whole database, as the bytes of a SQLite file.
    static func build(books: [Int: YouVersionBook], translation: Translation) throws -> Data {
        let db = try openMemory(contents: nil)
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
        // Bible joins verses (BibleRepository then looks them up); footnotes
        // only when it has some.
        let chapters = books.values.flatMap(\.chapters)
        if chapters.contains(where: \.joinsVerses) { try createSpans(db) }
        if chapters.contains(where: { !$0.notes.isEmpty }) { try createFootnotes(db) }
        let inserter = try Inserter(db)
        for number in books.keys.sorted() {
            for chapter in books[number]?.chapters ?? [] {
                try inserter.insert(chapter, book: number)
            }
        }
        inserter.finish()
        try execute(db, "COMMIT; INSERT INTO verses_fts(verses_fts) VALUES ('optimize');")
        return try serialize(db)
    }

    /// Writes the database to a plain file (tests; the app seals it instead).
    static func write(books: [Int: YouVersionBook], translation: Translation, to url: URL) throws {
        try build(books: books, translation: translation).write(to: url, options: .atomic)
    }

    /// The database with one chapter replaced by a newer copy from its
    /// source (verses, headings, joined verses, footnotes and the search
    /// index), as the bytes of a SQLite file.
    static func replacingChapter(_ chapter: YouVersionBook.Chapter, book: Int, in database: Data) throws -> Data {
        let db = try openMemory(contents: database)
        defer { sqlite3_close_v2(db) }
        let tables = try names(db, "SELECT name FROM sqlite_master WHERE type = 'table'")
        if chapter.joinsVerses, !tables.contains("verse_spans") { try createSpans(db) }
        if !chapter.notes.isEmpty, !tables.contains("footnotes") { try createFootnotes(db) }

        let first = VerseID(book: book, chapter: chapter.chapter, verse: 0).rawValue
        let last = VerseID(book: book, chapter: chapter.chapter, verse: 999).rawValue
        try execute(db, "BEGIN;")
        // A contentless search index forgets a row only when told its words.
        let old = try Statement(db, "SELECT id, text FROM verses WHERE id BETWEEN ? AND ?")
        let forget = try Statement(db, "INSERT INTO verses_fts(verses_fts, rowid, text) VALUES ('delete', ?, ?)")
        for (id, text) in try old.rows([.int(first), .int(last)]) {
            try forget.run([.int(id), .text(BibleSearchForm.indexed(text))])
        }
        old.finish()
        forget.finish()
        try execute(db, "DELETE FROM verses WHERE id BETWEEN \(first) AND \(last);")
        try execute(db, "DELETE FROM headings WHERE book = \(book) AND chapter = \(chapter.chapter);")
        let now = try names(db, "SELECT name FROM sqlite_master WHERE type = 'table'")
        if now.contains("verse_spans") { try execute(db, "DELETE FROM verse_spans WHERE id BETWEEN \(first) AND \(last);") }
        if now.contains("footnotes") { try execute(db, "DELETE FROM footnotes WHERE verse_id BETWEEN \(first) AND \(last);") }
        let inserter = try Inserter(db)
        try inserter.insert(chapter, book: book)
        inserter.finish()
        try execute(db, "COMMIT;")
        return try serialize(db)
    }

    // MARK: Pieces

    private static func createSpans(_ db: OpaquePointer) throws {
        try execute(db, "CREATE TABLE verse_spans (id INTEGER PRIMARY KEY, last INTEGER NOT NULL);")
    }

    private static func createFootnotes(_ db: OpaquePointer) throws {
        try execute(db, """
            CREATE TABLE footnotes (verse_id INTEGER NOT NULL, position INTEGER NOT NULL, text TEXT NOT NULL);
            CREATE INDEX footnotes_verse ON footnotes(verse_id);
            """)
    }

    /// Inserts one chapter's rows into whichever tables exist.
    private final class Inserter {
        private let verse: Statement
        private let heading: Statement
        private let search: Statement
        private let span: Statement?
        private let footnote: Statement?

        init(_ db: OpaquePointer) throws {
            let tables = try BibleFileWriter.names(db, "SELECT name FROM sqlite_master WHERE type = 'table'")
            verse = try Statement(db, "INSERT INTO verses VALUES (?, ?, ?, ?, ?, ?, ?)")
            heading = try Statement(db, "INSERT INTO headings VALUES (?, ?, ?, ?)")
            search = try Statement(db, "INSERT INTO verses_fts(rowid, text) VALUES (?, ?)")
            span = try (tables.contains("verse_spans") ? Statement(db, "INSERT INTO verse_spans VALUES (?, ?)") : nil)
            footnote = try (tables.contains("footnotes") ? Statement(db, "INSERT INTO footnotes VALUES (?, ?, ?)") : nil)
        }

        func insert(_ chapter: YouVersionBook.Chapter, book number: Int) throws {
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
            if let footnote {
                for note in chapter.notes where seen.contains(note.verse) && !note.text.isEmpty {
                    let id = VerseID(book: number, chapter: chapter.chapter, verse: note.verse).rawValue
                    try footnote.run([.int(id), .int(max(0, note.offset)), .text(note.text)])
                }
            }
        }

        func finish() {
            verse.finish()
            heading.finish()
            search.finish()
            span?.finish()
            footnote?.finish()
        }
    }

    /// An in-memory database: empty, or holding a SQLite file's bytes.
    private static func openMemory(contents: Data?) throws -> OpaquePointer {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw Failure.sqlite("open")
        }
        guard let contents else { return db }
        let size = contents.count
        guard size > 0, let buffer = sqlite3_malloc64(sqlite3_uint64(size))?.assumingMemoryBound(to: UInt8.self) else {
            sqlite3_close(db)
            throw Failure.sqlite("memory")
        }
        contents.copyBytes(to: buffer, count: size)
        // SQLite owns the buffer from here (and may grow it).
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE) | UInt32(SQLITE_DESERIALIZE_RESIZEABLE)
        guard sqlite3_deserialize(db, "main", buffer, sqlite3_int64(size), sqlite3_int64(size), flags) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw Failure.sqlite(message)
        }
        return db
    }

    /// The database's bytes, as a SQLite file holds them.
    private static func serialize(_ db: OpaquePointer) throws -> Data {
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(db, "main", &size, 0) else {
            throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_free(bytes) }
        return Data(bytes: bytes, count: Int(size))
    }

    private static func names(_ db: OpaquePointer, _ sql: String) throws -> Set<String> {
        let statement = try Statement(db, sql)
        defer { statement.finish() }
        return Set(try statement.texts())
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "exec"
            sqlite3_free(message)
            throw Failure.sqlite(text)
        }
    }

    /// A prepared statement, run once per row.
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

        private func bind(_ values: [Value]) throws -> OpaquePointer {
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
            return statement
        }

        func run(_ values: [Value]) throws {
            let statement = try bind(values)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }

        /// Rows of (integer, text), for reading what a chapter held.
        func rows(_ values: [Value]) throws -> [(Int, String)] {
            let statement = try bind(values)
            var rows: [(Int, String)] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw Failure.sqlite(String(cString: sqlite3_errmsg(db))) }
                let text = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                rows.append((Int(sqlite3_column_int64(statement, 0)), text))
            }
            return rows
        }

        /// The first column of every row, as text.
        func texts() throws -> [String] {
            let statement = try bind([])
            var texts: [String] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw Failure.sqlite(String(cString: sqlite3_errmsg(db))) }
                texts.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
            }
            return texts
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
