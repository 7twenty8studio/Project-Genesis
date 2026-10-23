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
    /// Only with Premium (a Bible whose licence Versely pays for).
    var premium: Bool = false
    /// Set for a YouVersion Platform Bible (public.youversion_bibles): its
    /// id on the Platform. It has no file; the device builds it book by book
    /// (`YouVersionBibleBuilder`).
    var youVersionID: Int?
    /// The publisher's website, linked from the copyright notice.
    var publisherURL: URL?

    /// The server's details, completed with what the app knows.
    var profile: TranslationProfile {
        TranslationProfile(approach: approach, readingLevel: readingLevel, rights: rights, popularity: popularity)
            .filling(from: TranslationProfile.builtIn[id])
            .filling(from: TranslationProfile(rights: TranslationProfile.rights(fromLicense: license)))
    }

    var translation: Translation {
        Translation(id: id, name: name, year: year, license: license, summary: summary, language: language, requiresPremium: premium, isYouVersion: youVersionID != nil, publisherURL: publisherURL)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, year, license, summary, version, sha256, language, approach, rights, popularity, premium
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
        premium = (try? container.decodeIfPresent(Bool.self, forKey: .premium)) ?? false
    }
}

/// A row of public.youversion_bibles: a YouVersion Platform Bible Versely
/// offers. Always free (no Premium column), never a file to download.
struct YouVersionCatalogRow: Decodable, Sendable {
    let id: String
    let yvpID: Int
    let name: String
    let year: String
    let license: String
    let summary: String
    let language: String
    let approach: String?
    let readingLevel: String?
    let popularity: Int?
    let version: Int
    let publisherURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, year, license, summary, language, approach, popularity, version
        case yvpID = "yvp_id"
        case readingLevel = "reading_level"
        case publisherURL = "publisher_url"
    }

    var downloadable: DownloadableTranslation {
        DownloadableTranslation(
            id: id, name: name, year: year, license: license, summary: summary,
            fileURL: "", fileBytes: 0, databaseBytes: 0, sha256: "", version: version,
            language: language,
            approach: approach.flatMap(TranslationApproach.init(rawValue:)),
            readingLevel: readingLevel.flatMap(ReadingLevel.init(rawValue:)),
            rights: .licensed,
            popularity: popularity,
            premium: false,
            youVersionID: yvpID,
            publisherURL: publisherURL.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        )
    }
}

/// A translation saved on this device, beyond (or replacing) the bundled ones.
struct InstalledTranslation: Codable, Hashable, Sendable {
    let translation: Translation
    let version: Int
    /// File name inside Application Support/Bibles.
    let fileName: String
    /// When it was downloaded (or built); nil for downloads saved before
    /// this was kept.
    var installedAt: Date?
    /// For a YouVersion Bible: the `YouVersionBibleBuilder.format` it was
    /// built with (nil: before footnotes and encryption). An older one is
    /// built again on Wi-Fi.
    var format: Int?
}

enum TranslationDownloadError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case damaged
    case notABible
    case needsPremium
    /// A YouVersion Bible's source asked us to slow down.
    case busy

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Downloads aren't set up in this build.")
        case .offline: String(localized: "You're offline. Connect to the internet to download Bibles.")
        case .damaged: String(localized: "The download was damaged. Please try again.")
        case .notABible: String(localized: "That file isn't a Bible Versely can read.")
        case .needsPremium: String(localized: "This Bible comes with Premium. If you subscribe, try Restore Purchases in Settings.")
        case .busy: String(localized: "Lots of people are downloading Bibles right now. Please try again in a few minutes; what's already downloaded is kept.")
        }
    }
}

/// What shows the server this device may download a Premium Bible: the
/// App Store subscription's signed transaction (no account needed) and, when
/// signed in, the account's token (for Premium granted by the owner).
struct PremiumProof: Sendable, Equatable {
    var accessToken: String?
    var signedTransaction: String?
}

/// Lists downloadable translations and downloads, checks and unpacks them.
/// BibleLibrary decides where they're stored and keeps track of them.
struct TranslationDownloader: Sendable {
    let client: SupabaseClient?

    /// Bible files (public.bible_translations), then YouVersion Platform
    /// Bibles (public.youversion_bibles). Throws unless both lists loaded, so
    /// a half-loaded catalog never makes BibleLibrary think a Bible was
    /// withdrawn.
    func catalog() async throws -> [DownloadableTranslation] {
        guard let client else { throw TranslationDownloadError.notConfigured }
        do {
            let files: [DownloadableTranslation] = try await client.select("bible_translations", query: [
                // All columns, so a server without the newer `language` column still works.
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "enabled", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort.asc,name.asc"),
            ])
            let youVersion: [YouVersionCatalogRow] = try await client.select("youversion_bibles", query: [
                URLQueryItem(name: "select", value: "id,yvp_id,name,year,license,summary,language,approach,reading_level,popularity,version,publisher_url"),
                URLQueryItem(name: "enabled", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort.asc,name.asc"),
            ])
            let fileIDs = Set(files.map(\.id))
            return files + youVersion.map(\.downloadable).filter { !fileIDs.contains($0.id) }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw TranslationDownloadError.offline
        }
    }

    /// Counts a finished YouVersion Bible download, anonymously, for the
    /// publishers' yearly reports (Lockman asks each February how many
    /// copies went out). Failures are ignored: a count is never worth an error.
    func recordDownload(_ item: DownloadableTranslation) async {
        guard let client, item.youVersionID != nil,
              let body = try? JSONEncoder().encode(["p_bible": item.id]) else { return }
        _ = try? await client.send("POST", path: "rest/v1/rpc/record_youversion_download", body: body, accessToken: nil)
    }

    /// Downloads a translation's file (or, for a YouVersion Bible, builds it
    /// on the device) to `destination`, and checks it holds a whole Bible.
    /// `progress` (YouVersion Bibles only) is called with the books in hand.
    func download(_ item: DownloadableTranslation, to destination: URL, allowsCellular: Bool = true, proof: PremiumProof? = nil, progress: (@Sendable (Int) -> Void)? = nil) async throws {
        if item.youVersionID != nil {
            guard let client else { throw TranslationDownloadError.notConfigured }
            try await YouVersionBibleBuilder(client: client).build(item, to: destination, allowsCellular: allowsCellular, progress: progress)
        } else {
            try await downloadFile(item, to: destination, allowsCellular: allowsCellular, proof: proof)
        }
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

    /// A Bible file from storage, unpacked and checked against the catalog.
    private func downloadFile(_ item: DownloadableTranslation, to destination: URL, allowsCellular: Bool, proof: PremiumProof?) async throws {
        let url = try await downloadURL(for: item, proof: proof)
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
    }

    /// Where to fetch the file. A licensed Bible sits in a private bucket:
    /// the bible-file function hands out a link that works for ten minutes,
    /// and only while the publisher's licence lets Versely offer it.
    private func downloadURL(for item: DownloadableTranslation, proof: PremiumProof?) async throws -> URL {
        guard item.rights == .licensed else {
            guard let url = URL(string: item.fileURL), url.scheme == "https" else { throw TranslationDownloadError.damaged }
            return url
        }
        guard let client else { throw TranslationDownloadError.notConfigured }
        // A Premium Bible also shows the subscription (or the account).
        var fields = ["id": item.id]
        if item.premium, let transaction = proof?.signedTransaction { fields["signedTransaction"] = transaction }
        let body = try JSONEncoder().encode(fields)
        let response: (data: Data, status: Int)
        do {
            response = try await client.callFunction("bible-file", body: body, accessToken: item.premium ? proof?.accessToken : nil)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw TranslationDownloadError.offline
        }
        struct Link: Decodable { let url: String }
        if response.status == 403 { throw TranslationDownloadError.needsPremium }
        guard response.status == 200,
              let link = try? JSONDecoder().decode(Link.self, from: response.data),
              let url = URL(string: link.url), url.scheme == "https" else {
            throw TranslationDownloadError.damaged
        }
        return url
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
