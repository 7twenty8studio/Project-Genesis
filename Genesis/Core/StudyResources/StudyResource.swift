import Foundation

/// What a study pack holds.
enum StudyResourceKind: String, Codable, CaseIterable, Sendable {
    case notes, commentary, dictionary, lexicon

    var title: String {
        switch self {
        case .notes: String(localized: "Study Notes", comment: "Study resource kind")
        case .commentary: String(localized: "Commentaries", comment: "Study resource kind")
        case .dictionary: String(localized: "Bible Dictionaries", comment: "Study resource kind")
        case .lexicon: String(localized: "Lexicons", comment: "Study resource kind: Hebrew and Greek dictionaries")
        }
    }

    var systemImage: String {
        switch self {
        case .notes: "text.book.closed"
        case .commentary: "books.vertical"
        case .dictionary: "character.book.closed"
        case .lexicon: "character.magnify"
        }
    }
}

/// The author's church tradition, shown so readers know the angle a
/// commentary comes from.
enum StudyTradition: String, Codable, Sendable {
    case evangelical, presbyterian, puritan, reformedBaptist = "reformed_baptist", wesleyan, reformed, lutheran, anglican

    var title: String {
        switch self {
        case .evangelical: String(localized: "Evangelical", comment: "Church tradition of a study resource")
        case .presbyterian: String(localized: "Presbyterian", comment: "Church tradition of a study resource")
        case .puritan: String(localized: "Puritan", comment: "Church tradition of a study resource")
        case .reformedBaptist: String(localized: "Reformed Baptist", comment: "Church tradition of a study resource")
        case .wesleyan: String(localized: "Wesleyan", comment: "Church tradition of a study resource")
        case .reformed: String(localized: "Reformed", comment: "Church tradition of a study resource")
        case .lutheran: String(localized: "Lutheran", comment: "Church tradition of a study resource")
        case .anglican: String(localized: "Anglican", comment: "Church tradition of a study resource")
        }
    }
}

/// A study pack that can be downloaded (public.study_resources).
struct DownloadableStudyResource: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: StudyResourceKind
    let name: String
    var author: String = ""
    var summary: String = ""
    var tradition: StudyTradition?
    var language: String = "en"
    var year: String?
    let license: String
    var attribution: String = ""
    /// Needs Premium (`.wordStudy`) to download and read.
    var premium: Bool = false
    let fileURL: String
    let fileBytes: Int
    let databaseBytes: Int
    let sha256: String
    let version: Int

    /// The app's own summary in the app's language where it has one; the
    /// server's otherwise.
    var localizedSummary: String {
        Self.builtInSummaries[id] ?? summary
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, author, summary, tradition, language, year, license, attribution, premium, sha256, version
        case fileURL = "file_url"
        case fileBytes = "file_bytes"
        case databaseBytes = "database_bytes"
    }

    private static let builtInSummaries: [String: String] = [
        "tyndale-notes": String(localized: "Verse-by-verse study notes, book introductions, and articles on people and themes."),
        "tyndale-dictionary": String(localized: "Thousands of articles on the Bible's people, places, customs and ideas."),
        "es-palabras": String(localized: "A Spanish dictionary of key Bible terms, names and ideas, linked to the verses that use them."),
        "jfb": String(localized: "A concise, careful commentary on the whole Bible, verse by verse."),
        "mhc": String(localized: "Henry's full devotional commentary on the whole Bible, section by section."),
        "barnes": String(localized: "Clear explanatory notes on the New Testament, written for teachers and families."),
        "gill": String(localized: "A detailed verse-by-verse exposition drawing on Hebrew and Jewish sources."),
        "clarke": String(localized: "A scholarly Methodist commentary with notes on language, history and customs."),
        "wesley": String(localized: "Brief, practical notes on the whole Bible from the founder of Methodism."),
        "calvin": String(localized: "The Reformer's commentaries on most books of the Bible, in English translation."),
        "keil-delitzsch": String(localized: "A thorough Old Testament commentary attentive to the Hebrew text."),
        "treasury-of-david": String(localized: "Spurgeon's devotional exposition of every psalm."),
        "burkitt": String(localized: "Practical, pastoral notes on the New Testament."),
        "lexicons": String(localized: "Brown-Driver-Briggs for Hebrew and the full Liddell-Scott-Jones for Greek, by Strong's number."),
    ]
}

extension DownloadableStudyResource {
    // In an extension so the memberwise initializer stays. Columns added
    // later, or a kind this version doesn't know, never hide the rest.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(StudyResourceKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        author = (try? container.decodeIfPresent(String.self, forKey: .author)) ?? ""
        summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        tradition = (try? container.decodeIfPresent(String.self, forKey: .tradition)).flatMap(StudyTradition.init(rawValue:))
        language = (try? container.decodeIfPresent(String.self, forKey: .language)) ?? "en"
        year = try? container.decodeIfPresent(String.self, forKey: .year)
        license = try container.decode(String.self, forKey: .license)
        attribution = (try? container.decodeIfPresent(String.self, forKey: .attribution)) ?? ""
        premium = (try? container.decodeIfPresent(Bool.self, forKey: .premium)) ?? false
        fileURL = try container.decode(String.self, forKey: .fileURL)
        fileBytes = try container.decode(Int.self, forKey: .fileBytes)
        databaseBytes = try container.decode(Int.self, forKey: .databaseBytes)
        sha256 = try container.decode(String.self, forKey: .sha256)
        version = try container.decode(Int.self, forKey: .version)
    }

    /// Decodes a catalog, leaving out rows this version can't use (a new
    /// kind) instead of failing the whole list.
    static func decodeCatalog(_ data: Data) throws -> [DownloadableStudyResource] {
        try JSONDecoder().decode([CatalogRow].self, from: data).compactMap(\.item)
    }

    /// One catalog row, nil when this version can't use it.
    struct CatalogRow: Decodable, Sendable {
        let item: DownloadableStudyResource?
        init(from decoder: Decoder) throws {
            item = try? DownloadableStudyResource(from: decoder)
        }
    }
}

/// A pack saved on this device.
struct InstalledStudyResource: Codable, Hashable, Sendable {
    let resource: DownloadableStudyResource
    /// File name inside Application Support/StudyResources.
    let fileName: String
}

enum StudyResourceDownloadError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case damaged
    case notAStudyPack

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Downloads aren't set up in this build.")
        case .offline: String(localized: "You're offline. Connect to the internet to download study resources.")
        case .damaged: String(localized: "The download was damaged. Please try again.")
        case .notAStudyPack: String(localized: "That file isn't a study resource Genesis can read.")
        }
    }
}

/// Lists downloadable study packs and downloads, checks and unpacks them.
/// StudyResourceLibrary decides where they're stored.
struct StudyResourceDownloader: Sendable {
    let client: SupabaseClient?

    private static let offlineCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut]

    func catalog() async throws -> [DownloadableStudyResource] {
        guard let client else { throw StudyResourceDownloadError.notConfigured }
        do {
            let rows: [DownloadableStudyResource.CatalogRow] = try await client.select("study_resources", query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "enabled", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort.asc,name.asc"),
            ])
            return rows.compactMap(\.item)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw StudyResourceDownloadError.offline
        }
    }

    /// Downloads, unpacks and checks a pack, writing the SQLite file to `destination`.
    func download(_ item: DownloadableStudyResource, to destination: URL, allowsCellular: Bool = true) async throws {
        guard let url = URL(string: item.fileURL), url.scheme == "https" else { throw StudyResourceDownloadError.damaged }
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.timeoutInterval = 300
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw StudyResourceDownloadError.offline
        }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            throw StudyResourceDownloadError.damaged
        }
        let database: Data
        do {
            database = try TranslationDownloader.unpack(data, expectedBytes: item.databaseBytes, sha256: item.sha256)
        } catch {
            throw StudyResourceDownloadError.damaged
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try database.write(to: destination, options: .atomic)
        // Downloads can be fetched again, so they don't need iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = destination
        try? file.setResourceValues(values)
        // Make sure it opens and is the pack the catalog promised.
        do {
            let repository = try StudyResourceRepository(url: destination)
            guard try repository.packID() == item.id else { throw StudyResourceDownloadError.notAStudyPack }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw StudyResourceDownloadError.notAStudyPack
        }
    }
}
