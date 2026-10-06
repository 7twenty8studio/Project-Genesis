import CryptoKit
import Foundation

/// A translation that can be downloaded (public.bible_translations).
struct DownloadableTranslation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let year: String
    let license: String
    let summary: String
    let fileURL: String
    let fileBytes: Int
    let databaseBytes: Int
    let sha256: String
    let version: Int
    /// "en", "es". Older catalogs without the column are English.
    var language: String = "en"
    /// The Bibles screen's details; nil where the server doesn't say.
    var approach: TranslationApproach?
    var readingLevel: ReadingLevel?
    var rights: TranslationRights?
    var popularity: Int?

    /// The server's details, completed with what the app knows.
    var profile: TranslationProfile {
        TranslationProfile(approach: approach, readingLevel: readingLevel, rights: rights, popularity: popularity)
            .filling(from: TranslationProfile.builtIn[id])
            .filling(from: TranslationProfile(rights: TranslationProfile.rights(fromLicense: license)))
    }

    var translation: Translation {
        Translation(id: id, name: name, year: year, license: license, summary: summary, language: language)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, year, license, summary, version, sha256, language, approach, rights, popularity
        case readingLevel = "reading_level"
        case fileURL = "file_url"
        case fileBytes = "file_bytes"
        case databaseBytes = "database_bytes"
    }
}

extension DownloadableTranslation {
    // In an extension so the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        year = try container.decode(String.self, forKey: .year)
        license = try container.decode(String.self, forKey: .license)
        summary = try container.decode(String.self, forKey: .summary)
        fileURL = try container.decode(String.self, forKey: .fileURL)
        fileBytes = try container.decode(Int.self, forKey: .fileBytes)
        databaseBytes = try container.decode(Int.self, forKey: .databaseBytes)
        sha256 = try container.decode(String.self, forKey: .sha256)
        version = try container.decode(Int.self, forKey: .version)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        // Newer columns: an older server, or a value this version doesn't
        // know, leaves them empty rather than hiding the Bible.
        approach = (try? container.decodeIfPresent(String.self, forKey: .approach)).flatMap(TranslationApproach.init(rawValue:))
        readingLevel = (try? container.decodeIfPresent(String.self, forKey: .readingLevel)).flatMap(ReadingLevel.init(rawValue:))
        rights = (try? container.decodeIfPresent(String.self, forKey: .rights)).flatMap(TranslationRights.init(rawValue:))
        popularity = try? container.decodeIfPresent(Int.self, forKey: .popularity)
    }
}

/// A translation saved on this device, beyond (or replacing) the bundled ones.
struct InstalledTranslation: Codable, Hashable, Sendable {
    let translation: Translation
    let version: Int
    /// File name inside Application Support/Bibles.
    let fileName: String
}

enum TranslationDownloadError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case damaged
    case notABible

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Downloads aren't set up in this build.")
        case .offline: String(localized: "You're offline. Connect to the internet to download Bibles.")
        case .damaged: String(localized: "The download was damaged. Please try again.")
        case .notABible: String(localized: "That file isn't a Bible Genesis can read.")
        }
    }
}

/// Lists downloadable translations and downloads, checks and unpacks them.
/// BibleLibrary decides where they're stored and keeps track of them.
struct TranslationDownloader: Sendable {
    let client: SupabaseClient?

    func catalog() async throws -> [DownloadableTranslation] {
        guard let client else { throw TranslationDownloadError.notConfigured }
        do {
            return try await client.select("bible_translations", query: [
                // All columns, so a server without the newer `language` column still works.
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "enabled", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort.asc,name.asc"),
            ])
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw TranslationDownloadError.offline
        }
    }

    /// Downloads, unpacks and checks a translation; returns the SQLite bytes
    /// written to `destination`.
    func download(_ item: DownloadableTranslation, to destination: URL, allowsCellular: Bool = true) async throws {
        guard let url = URL(string: item.fileURL), url.scheme == "https" else { throw TranslationDownloadError.damaged }
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.timeoutInterval = 120
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw TranslationDownloadError.offline
        }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            throw TranslationDownloadError.damaged
        }
        let database = try Self.unpack(data, expectedBytes: item.databaseBytes, sha256: item.sha256)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try database.write(to: destination, options: .atomic)
        // Downloads can be fetched again, so they don't need iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = destination
        try? file.setResourceValues(values)
        // Make sure it opens and has a whole Bible before using it.
        do {
            let repository = try BibleRepository(translation: item.translation, url: destination)
            guard try repository.verseCount() > 30_000 else { throw TranslationDownloadError.notABible }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw TranslationDownloadError.notABible
        }
    }

    /// Raw DEFLATE → SQLite, checked against the catalog's size and hash.
    static func unpack(_ data: Data, expectedBytes: Int, sha256: String) throws -> Data {
        guard let database = try? (data as NSData).decompressed(using: .zlib) as Data,
              database.count == expectedBytes else {
            throw TranslationDownloadError.damaged
        }
        let digest = SHA256.hash(data: database).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256.lowercased() else { throw TranslationDownloadError.damaged }
        return database
    }
}
