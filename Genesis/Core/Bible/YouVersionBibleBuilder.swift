import Foundation

/// One book of a YouVersion Platform Bible, as the yvp-bible Edge Function
/// returns it: verses verbatim (the function's parser keeps every word;
/// supabase/functions/yvp-bible/lib.ts), the translation's headings,
/// bridged verses ("16–17") on their first verse, and the footnotes, apart
/// from the text.
struct YouVersionBook: Codable, Sendable, Equatable {
    struct Chapter: Codable, Sendable, Equatable {
        let chapter: Int
        let verses: [Verse]
        let headings: [Heading]
        /// Footnotes (empty from books fetched before notes were sent).
        var notes: [Note] = []
        /// Seconds the Platform lets this copy be used before fetching it
        /// again when online (its Cache-Control); nil from older books.
        var maxAge: Int?

        var joinsVerses: Bool { verses.contains { ($0.last ?? 0) > $0.verse } }

        init(chapter: Int, verses: [Verse], headings: [Heading], notes: [Note] = [], maxAge: Int? = nil) {
            self.chapter = chapter
            self.verses = verses
            self.headings = headings
            self.notes = notes
            self.maxAge = maxAge
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            chapter = try container.decode(Int.self, forKey: .chapter)
            verses = try container.decode([Verse].self, forKey: .verses)
            headings = try container.decode([Heading].self, forKey: .headings)
            notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
            maxAge = try container.decodeIfPresent(Int.self, forKey: .maxAge)
        }

        /// The same words, headings and notes (when it was fetched aside).
        func hasSameText(as other: Chapter) -> Bool {
            chapter == other.chapter && verses == other.verses && headings == other.headings && notes == other.notes
        }
    }

    struct Note: Codable, Sendable, Equatable {
        let verse: Int
        /// UTF-16 offset in the verse's text where the marker goes.
        let offset: Int
        let text: String
    }

    struct Verse: Codable, Sendable, Equatable {
        let verse: Int
        /// Set for a bridged verse: the last verse it holds.
        let last: Int?
        let text: String
        let paragraph: Bool
        let poetry: Bool
    }

    struct Heading: Codable, Sendable, Equatable {
        let beforeVerse: Int
        let text: String
    }

    let chapters: [Chapter]
}

/// Builds a YouVersion Platform Bible on the device: fetches it book by book
/// through the yvp-bible function (which holds the Platform key) and writes
/// a database in the app's Bible format (`BibleFileWriter`), sealed with
/// this device's key (`BibleProtection`), so it reads offline like any other
/// Bible while its text never sits in a readable file.
///
/// The publishers allow these Bibles to be downloaded in a mobile app
/// (Biblica: "downloadable for mobile software applications"; Lockman:
/// "download to the user's device") with their conditions: every footnote
/// shown, the text encrypted, a link to the publisher (LICENSED_BIBLES.md
/// › 5). A chapter is fetched again when it's opened online after the
/// Platform's Cache-Control lifetime (`YouVersionFreshness`, BibleLibrary).
struct YouVersionBibleBuilder: Sendable {
    let client: SupabaseClient

    /// What a build holds: 2 = footnotes, sealed. Bibles built before are
    /// built again (BibleLibrary, on Wi-Fi).
    static let format = 2

    /// USFM codes of the 66 books, in the app's order (book 1 = GEN).
    static let bookCodes = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH",
        "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS",
        "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL",
        "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH",
        "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
    ]

    /// Books fetched at once (each is one function call that reads every
    /// chapter of the book from the Platform, four at a time). Kept low:
    /// the Platform limits requests per app key, shared by every reader.
    private static let parallelBooks = 2

    /// Where an unfinished download keeps the books it has (sealed): until
    /// the Bible is built, so a download stopped by the Platform's rate
    /// limit (or the network) carries on where it left off.
    static func partsFolder(for item: DownloadableTranslation, in folder: URL) -> URL {
        folder.appending(path: "\(item.id)-\(item.version)-books", directoryHint: .isDirectory)
    }

    /// How many books an unfinished download already has (0 when none).
    /// Reads only the small index (cheap enough for a screen to ask).
    static func savedBookCount(for item: DownloadableTranslation, in folder: URL) -> Int {
        savedDates(in: partsFolder(for: item, in: folder)).count
    }

    /// When each saved book was fetched, for those recent enough to use (a
    /// week), from the parts folder's index (kept by the download itself, so
    /// no file dates are read).
    private static func savedDates(in parts: URL) -> [Int: Date] {
        guard let data = try? Data(contentsOf: parts.appending(path: "index.json")),
              let index = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        var dates: [Int: Date] = [:]
        for (key, seconds) in index {
            guard let number = Int(key) else { continue }
            let saved = Date(timeIntervalSince1970: seconds)
            let file = parts.appending(path: "\(number).json")
            if Date.now.timeIntervalSince(saved) < 7 * 24 * 60 * 60,
               FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                dates[number] = saved
            }
        }
        return dates
    }

    private static func saveIndex(_ dates: [Int: Date], in parts: URL) {
        let index = Dictionary(uniqueKeysWithValues: dates.map { (String($0.key), $0.value.timeIntervalSince1970) })
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: parts.appending(path: "index.json"), options: .atomic)
    }

    /// Forgets an unfinished download.
    static func discard(_ item: DownloadableTranslation, in folder: URL) {
        try? FileManager.default.removeItem(at: partsFolder(for: item, in: folder))
    }

    /// `progress` is called with how many of the 66 books are in hand.
    func build(_ item: DownloadableTranslation, to destination: URL, allowsCellular: Bool, progress: (@Sendable (Int) -> Void)? = nil) async throws {
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let parts = Self.partsFolder(for: item, in: folder)
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var partsURL = parts
        try? partsURL.setResourceValues(values)

        let fetched = try await fetchAll(id: item.id, parts: parts, allowsCellular: allowsCellular, progress: progress)
        let books = fetched.books
        // Built in memory and written sealed in one step: the text never
        // reaches the disk readable, and a half-built file is never opened.
        try BibleProtection.write(try BibleFileWriter.build(books: books, translation: item.translation), to: destination)
        // When each chapter must be fetched again if it's opened online.
        var freshness = YouVersionFreshness()
        for (number, book) in books {
            let when = fetched.dates[number] ?? .now
            for chapter in book.chapters {
                freshness.set(book: number, chapter: chapter.chapter, fetchedAt: when, maxAge: chapter.maxAge)
            }
        }
        freshness.save(for: item.id, in: folder)
        try? FileManager.default.removeItem(at: parts)
    }

    /// One chapter, fetched again (a chapter shown online after its lifetime).
    /// Nil when the Bible doesn't have it.
    func fetchChapter(id: String, book number: Int, chapter: Int) async throws -> YouVersionBook.Chapter? {
        guard Self.bookCodes.indices.contains(number - 1) else { return nil }
        struct Request: Encodable { let id: String; let book: String; let chapter: Int }
        let body = try JSONEncoder().encode(Request(id: id, book: Self.bookCodes[number - 1], chapter: chapter))
        let response = try await client.callFunction("yvp-bible", body: body, accessToken: nil, timeout: 30)
        switch response.status {
        case 200:
            let book = try JSONDecoder().decode(YouVersionBook.self, from: response.data)
            return book.chapters.first { $0.chapter == chapter }
        case 404:
            return nil
        case 429:
            throw TranslationDownloadError.busy
        default:
            throw TranslationDownloadError.damaged
        }
    }

    /// A book saved by an earlier, unfinished download.
    fileprivate static func savedBook(_ number: Int, in parts: URL) -> YouVersionBook? {
        guard let data = try? BibleProtection.read(parts.appending(path: "\(number).json")) else { return nil }
        return try? JSONDecoder().decode(YouVersionBook.self, from: data)
    }

    /// Every book (book number → its chapters), and when each was fetched.
    private func fetchAll(id: String, parts: URL, allowsCellular: Bool, progress: (@Sendable (Int) -> Void)?) async throws -> (books: [Int: YouVersionBook], dates: [Int: Date]) {
        let codes = Self.bookCodes
        var books: [Int: YouVersionBook] = [:]
        var dates: [Int: Date] = [:]
        var missing: [Int] = []
        let saved = Self.savedDates(in: parts)
        for number in 1...codes.count {
            if let date = saved[number], let book = Self.savedBook(number, in: parts) {
                books[number] = book
                dates[number] = date
            } else {
                missing.append(number)
            }
        }
        progress?(books.count)
        return try await withThrowingTaskGroup(of: (Int, YouVersionBook).self) { group in
            var next = 0
            while next < min(Self.parallelBooks, missing.count) {
                let number = missing[next]
                next += 1
                group.addTask { (number, try await self.fetchBook(id: id, code: codes[number - 1], number: number, parts: parts, allowsCellular: allowsCellular)) }
            }
            while let (number, book) = try await group.next() {
                books[number] = book
                dates[number] = .now
                // Noted here, one book at a time, so a stopped download
                // knows what it has.
                Self.saveIndex(dates, in: parts)
                progress?(books.count)
                if next < missing.count {
                    let number = missing[next]
                    next += 1
                    group.addTask { (number, try await self.fetchBook(id: id, code: codes[number - 1], number: number, parts: parts, allowsCellular: allowsCellular)) }
                }
            }
            return (books, dates)
        }
    }

    /// One book, tried up to three times (the Platform can be briefly busy).
    private func fetchBook(id: String, code: String, number: Int, parts: URL, allowsCellular: Bool) async throws -> YouVersionBook {
        let body = try JSONEncoder().encode(["id": id, "book": code])
        var attempt = 0
        while true {
            try Task.checkCancellation()
            attempt += 1
            let response: (data: Data, status: Int)
            do {
                response = try await client.callFunction("yvp-bible", body: body, accessToken: nil, allowsCellular: allowsCellular, timeout: 90)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
                throw TranslationDownloadError.offline
            } catch let error as URLError where error.code == .timedOut && attempt < 3 {
                try await Task.sleep(for: .seconds(2 * attempt))
                continue
            } catch let error as URLError where error.code == .timedOut {
                // Online, but a book kept taking too long: the source is busy.
                throw TranslationDownloadError.busy
            }
            switch response.status {
            case 200:
                guard let book = try? JSONDecoder().decode(YouVersionBook.self, from: response.data), !book.chapters.isEmpty else {
                    throw TranslationDownloadError.damaged
                }
                // Kept sealed until the Bible is built (licensed text).
                try? BibleProtection.write(response.data, to: parts.appending(path: "\(number).json"))
                return book
            case 429:
                // The Platform is busy (it limits requests per app key).
                throw TranslationDownloadError.busy
            case 500...599 where attempt < 3:
                try await Task.sleep(for: .seconds(2 * attempt))
            default:
                // 404: the Bible left the catalog; anything else: try later.
                throw TranslationDownloadError.damaged
            }
        }
    }
}

/// When each chapter of a YouVersion Bible on this device must be fetched
/// again if it's opened online: the Platform's Cache-Control lifetime from
/// when it was fetched (YouVersion: following that header is how caching
/// complies). Kept beside the Bible as JSON (times only, no text).
struct YouVersionFreshness: Codable, Sendable, Equatable {
    /// "book.chapter" → when it goes stale (seconds since 1970).
    private var staleAfter: [String: Double] = [:]

    /// The Platform's usual lifetime, for chapters fetched without one.
    static let defaultMaxAge = 3600

    mutating func set(book: Int, chapter: Int, fetchedAt: Date, maxAge: Int?) {
        let lifetime = TimeInterval(max(0, maxAge ?? Self.defaultMaxAge))
        staleAfter["\(book).\(chapter)"] = fetchedAt.addingTimeInterval(lifetime).timeIntervalSince1970
    }

    /// True when the chapter should be fetched again before it's trusted
    /// online (also when nothing is known about it).
    func isStale(book: Int, chapter: Int, now: Date = .now) -> Bool {
        guard let limit = staleAfter["\(book).\(chapter)"] else { return true }
        return now.timeIntervalSince1970 >= limit
    }

    static func url(for id: String, in folder: URL) -> URL {
        folder.appending(path: "\(id).freshness.json")
    }

    static func load(for id: String, in folder: URL) -> YouVersionFreshness {
        guard let data = try? Data(contentsOf: url(for: id, in: folder)),
              let value = try? JSONDecoder().decode(YouVersionFreshness.self, from: data) else { return YouVersionFreshness() }
        return value
    }

    func save(for id: String, in folder: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url(for: id, in: folder), options: .atomic)
    }

    static func remove(for id: String, in folder: URL) {
        try? FileManager.default.removeItem(at: url(for: id, in: folder))
    }
}

/// Whether a chapter fetched again differs from the one stored, compared
/// as the Bible file keeps it (verses with words, once each; headings and
/// notes of those verses), so an unchanged chapter is never rewritten.
enum YouVersionChapterComparison {
    static func differs(stored: Chapter, fresh: YouVersionBook.Chapter) -> Bool {
        normalized(fresh) != normalized(asBook(stored))
    }

    static func asBook(_ chapter: Chapter) -> YouVersionBook.Chapter {
        YouVersionBook.Chapter(
            chapter: chapter.id.chapter,
            verses: chapter.verses.map {
                YouVersionBook.Verse(verse: $0.id.verse, last: $0.lastVerse, text: $0.text, paragraph: $0.startsParagraph, poetry: $0.isPoetry)
            },
            headings: chapter.headings.map { YouVersionBook.Heading(beforeVerse: $0.beforeVerse, text: $0.text) },
            notes: chapter.footnotes.map { YouVersionBook.Note(verse: $0.verse.verse, offset: $0.offset, text: $0.text) }
        )
    }

    static func normalized(_ chapter: YouVersionBook.Chapter) -> YouVersionBook.Chapter {
        var seen = Set<Int>()
        let verses = chapter.verses
            .filter { !$0.text.isEmpty && seen.insert($0.verse).inserted }
            .map { YouVersionBook.Verse(verse: $0.verse, last: ($0.last ?? 0) > $0.verse ? $0.last : nil, text: $0.text, paragraph: $0.paragraph, poetry: $0.poetry) }
            .sorted { $0.verse < $1.verse }
        let headings = chapter.headings
            .filter { seen.contains($0.beforeVerse) }
            .enumerated()
            .sorted { ($0.element.beforeVerse, $0.offset) < ($1.element.beforeVerse, $1.offset) }
            .map(\.element)
        let notes = chapter.notes
            .filter { seen.contains($0.verse) && !$0.text.isEmpty }
            .map { YouVersionBook.Note(verse: $0.verse, offset: max(0, $0.offset), text: $0.text) }
            .enumerated()
            .sorted { ($0.element.verse, $0.element.offset, $0.offset) < ($1.element.verse, $1.element.offset, $1.offset) }
            .map(\.element)
        return YouVersionBook.Chapter(chapter: chapter.chapter, verses: verses, headings: headings, notes: notes)
    }
}
