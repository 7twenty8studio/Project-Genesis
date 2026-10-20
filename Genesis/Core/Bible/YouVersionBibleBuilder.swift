import Foundation

/// One book of a YouVersion Platform Bible, as the yvp-bible Edge Function
/// returns it: verses verbatim (the function's parser keeps every word;
/// supabase/functions/yvp-bible/lib.ts), the translation's headings, and
/// bridged verses ("16–17") on their first verse.
struct YouVersionBook: Decodable, Sendable, Equatable {
    struct Chapter: Decodable, Sendable, Equatable {
        let chapter: Int
        let verses: [Verse]
        let headings: [Heading]
    }

    struct Verse: Decodable, Sendable, Equatable {
        let verse: Int
        /// Set for a bridged verse: the last verse it holds.
        let last: Int?
        let text: String
        let paragraph: Bool
        let poetry: Bool
    }

    struct Heading: Decodable, Sendable, Equatable {
        let beforeVerse: Int
        let text: String
    }

    let chapters: [Chapter]
}

/// Builds a YouVersion Platform Bible on the device: fetches it book by book
/// through the yvp-bible function (which holds the Platform key) and writes
/// a database in the app's Bible format (`BibleFileWriter`), so it reads
/// offline like any other Bible.
///
/// YouVersion agreed that its Bibles may be stored on the device, unless a
/// publisher limits caching, and asked that they be refreshed when online
/// (LICENSED_BIBLES.md › 5): BibleLibrary builds them again on Wi-Fi once a
/// month, and removes them when they leave the catalog.
struct YouVersionBibleBuilder: Sendable {
    let client: SupabaseClient

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

    func build(_ item: DownloadableTranslation, to destination: URL, allowsCellular: Bool) async throws {
        let books = try await fetchAll(id: item.id, allowsCellular: allowsCellular)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written beside the destination, then moved in, so a half-built file
        // is never opened.
        let partial = destination.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        do {
            try BibleFileWriter.write(books: books, translation: item.translation, to: partial)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Every book, in order (book number → its chapters).
    private func fetchAll(id: String, allowsCellular: Bool) async throws -> [Int: YouVersionBook] {
        let codes = Self.bookCodes
        return try await withThrowingTaskGroup(of: (Int, YouVersionBook).self) { group in
            var next = 0
            var books: [Int: YouVersionBook] = [:]
            while next < min(Self.parallelBooks, codes.count) {
                let index = next
                next += 1
                group.addTask { (index + 1, try await self.fetchBook(id: id, code: codes[index], allowsCellular: allowsCellular)) }
            }
            while let (number, book) = try await group.next() {
                books[number] = book
                if next < codes.count {
                    let index = next
                    next += 1
                    group.addTask { (index + 1, try await self.fetchBook(id: id, code: codes[index], allowsCellular: allowsCellular)) }
                }
            }
            return books
        }
    }

    /// One book, tried up to three times (the Platform can be briefly busy).
    private func fetchBook(id: String, code: String, allowsCellular: Bool) async throws -> YouVersionBook {
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
