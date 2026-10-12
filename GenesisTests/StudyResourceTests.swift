import Foundation
import SQLite3
import Testing
@testable import Genesis

// The Study Library: downloadable study notes, commentaries, dictionaries
// and lexicons (Tools/StudyResources/build_resources.py writes the packs).

@Suite("Study pack markup")
struct StudyMarkupTests {
    @Test func splitsHeadingsListItemsAndParagraphs() {
        let blocks = StudyMarkup.blocks("## The Fall\n\nFirst *paragraph*.\n\n- an item\n\n\n\nLast")
        #expect(blocks == [.heading("The Fall"), .paragraph("First *paragraph*."), .listItem("an item"), .paragraph("Last")])
    }

    @Test func escapedDashStaysAParagraph() {
        #expect(StudyMarkup.blocks("\\- not a list") == [.paragraph("\\- not a list")])
        #expect(StudyMarkup.plain("\\- not a list") == "- not a list")
    }

    @Test func readsVerseLinks() throws {
        let range = try #require(URL(string: "verse:1001001-1002003"))
        #expect(StudyMarkup.link(range) == .verses(StudyRange(start: VerseID(rawValue: 1_001_001), end: VerseID(rawValue: 1_002_003))))
        let single = try #require(URL(string: "verse:43003016"))
        #expect(StudyMarkup.link(single) == .verses(StudyRange(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_016))))
        let broken = try #require(URL(string: "verse:abc"))
        #expect(StudyMarkup.link(broken) == nil)
    }

    @Test func readsArticleLinksWithSlashesInTheID() throws {
        let url = try #require(URL(string: "article:es-palabras/kt/adoption"))
        #expect(StudyMarkup.link(url) == .article(pack: "es-palabras", id: "kt/adoption"))
        let plain = try #require(URL(string: "article:tyndale-notes/Aaron"))
        #expect(StudyMarkup.link(plain) == .article(pack: "tyndale-notes", id: "Aaron"))
        let web = try #require(URL(string: "https://example.com"))
        #expect(StudyMarkup.link(web) == nil)
    }

    @Test func linksSurviveTheMarkdown() {
        let text = StudyMarkup.attributed("See [John 3:16](verse:43003016) and *grace*.")
        #expect(String(text.characters) == "See John 3:16 and grace.")
        #expect(text.runs.contains { $0.link?.absoluteString == "verse:43003016" })
    }

    @Test func foldsCaseAndAccents() {
        #expect(StudyMarkup.folded("  Ádán ") == "adan")
        #expect(StudyMarkup.folded("ESPÍRITU Santo") == "espiritu santo")
    }

    @Test func escapesLikeWildcards() {
        #expect(StudyMarkup.likeEscaped("50%_off\\") == "50\\%\\_off\\\\")
    }
}

@Suite("Study ranges")
struct StudyRangeTests {
    @Test func describesPassages() {
        let genesis = StudyRange(start: VerseID(book: 1, chapter: 1, verse: 1), end: VerseID(book: 1, chapter: 2, verse: 3))
        #expect(genesis.description(in: "en") == "Genesis 1:1\u{2013}2:3")
        let john = StudyRange(start: VerseID(book: 43, chapter: 3, verse: 16), end: VerseID(book: 43, chapter: 3, verse: 16))
        #expect(john.description(in: "en") == "John 3:16")
        let verses = StudyRange(start: VerseID(book: 43, chapter: 3, verse: 16), end: VerseID(book: 43, chapter: 3, verse: 18))
        #expect(verses.description(in: "en") == "John 3:16\u{2013}18")
        let jude = StudyRange(start: VerseID(book: 65, chapter: 1, verse: 3), end: VerseID(book: 65, chapter: 1, verse: 3))
        #expect(jude.description(in: "en") == "Jude 3")
    }

    @Test func chapterIntroductionsUseVerseZero() {
        let intro = StudyRange(start: VerseID(book: 1, chapter: 3, verse: 0), end: VerseID(book: 1, chapter: 3, verse: 24))
        #expect(intro.isChapterIntroduction)
        #expect(intro.description(in: "en") == "Genesis 3")
        #expect(intro.covers(VerseID(book: 1, chapter: 3, verse: 15)))
        #expect(!intro.covers(VerseID(book: 1, chapter: 4, verse: 1)))
    }

    @Test func endNeverComesBeforeStart() {
        let range = StudyRange(start: VerseID(book: 1, chapter: 1, verse: 3), end: VerseID(book: 1, chapter: 1, verse: 2))
        #expect(range.end == range.start)
    }
}

@Suite("Study resource catalog")
struct StudyResourceCatalogTests {
    private static func row(id: String, kind: String, extra: String = "") -> String {
        """
        {"id":"\(id)","kind":"\(kind)","name":"\(id)","license":"Public domain","file_url":"https://example.com/\(id).deflate",
         "file_bytes":10,"database_bytes":20,"sha256":"abc","version":2\(extra)}
        """
    }

    @Test func decodesRowsAndSkipsKindsItDoesNotKnow() throws {
        let json = "[\(Self.row(id: "mhc", kind: "commentary", extra: #","premium":true,"tradition":"puritan","year":"1706","author":"Matthew Henry""#)),\(Self.row(id: "maps", kind: "atlas"))]"
        let items = try DownloadableStudyResource.decodeCatalog(Data(json.utf8))
        #expect(items.map(\.id) == ["mhc"])
        let mhc = try #require(items.first)
        #expect(mhc.kind == .commentary)
        #expect(mhc.premium)
        #expect(mhc.tradition == .puritan)
        #expect(mhc.year == "1706")
        #expect(mhc.language == "en")
        #expect(mhc.version == 2)
    }

    @Test func unknownTraditionsAndMissingColumnsAreLenient() throws {
        let json = "[\(Self.row(id: "tyndale-notes", kind: "notes", extra: #","tradition":"new-one","summary":null"#))]"
        let item = try #require(try DownloadableStudyResource.decodeCatalog(Data(json.utf8)).first)
        #expect(item.tradition == nil)
        #expect(item.summary == "")
        #expect(!item.premium)
        #expect(item.author == "")
    }

    @Test func installedPacksRoundTrip() throws {
        let json = "[\(Self.row(id: "wesley", kind: "commentary", extra: #","tradition":"wesleyan""#))]"
        let item = try #require(try DownloadableStudyResource.decodeCatalog(Data(json.utf8)).first)
        let installed = InstalledStudyResource(resource: item, fileName: "wesley-2.sqlite")
        let data = try JSONEncoder().encode([installed])
        let decoded = try JSONDecoder().decode([InstalledStudyResource].self, from: data)
        #expect(decoded == [installed])
    }
}

@Suite("Study resource packs")
struct StudyResourceRepositoryTests {
    /// A tiny pack in the build tool's format.
    private static func makePack() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "study-pack-\(UUID().uuidString).sqlite")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path(percentEncoded: false), &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE info(key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO info VALUES ('id','test-pack'),('kind','notes');
        CREATE TABLE notes(id INTEGER PRIMARY KEY, start_verse INTEGER, end_verse INTEGER, title TEXT, text TEXT);
        INSERT INTO notes VALUES (1, 43003016, 43003016, NULL, 'Verse note.');
        INSERT INTO notes VALUES (2, 43003000, 43003036, 'Chapter', 'Chapter introduction.');
        INSERT INTO notes VALUES (3, 43003014, 43003021, NULL, 'Wider note.');
        INSERT INTO notes VALUES (4, 43004001, 43004002, NULL, 'Next chapter.');
        CREATE TABLE introductions(book INTEGER PRIMARY KEY, title TEXT, text TEXT);
        INSERT INTO introductions VALUES (43, 'John', 'The fourth Gospel.');
        CREATE TABLE articles(id TEXT PRIMARY KEY, title TEXT, kind TEXT, sort_key TEXT, text TEXT);
        INSERT INTO articles VALUES ('Nicodemus','Nicodemus','profile','nicodemus','A Pharisee.');
        INSERT INTO articles VALUES ('kt/espiritu','Espíritu','keyterm','espiritu','El Espíritu.');
        INSERT INTO articles VALUES ('kt/santo','Espíritu Santo, el','keyterm','santo espiritu','Santo.');
        INSERT INTO articles VALUES ('pct','50% off','term','50% off','A percent.');
        CREATE TABLE article_verses(article TEXT, start_verse INTEGER, end_verse INTEGER);
        INSERT INTO article_verses VALUES ('Nicodemus', 43003001, 43003021);
        INSERT INTO article_verses VALUES ('kt/espiritu', 43003005, 43003008);
        CREATE TABLE lexicon(strongs TEXT, source TEXT, lemma TEXT, translit TEXT, gloss TEXT, definition TEXT);
        INSERT INTO lexicon VALUES ('H0430','bdb','אֱלֹהִים','elohim','God','**God**, gods.');
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    @Test func readsItsID() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        #expect(try repository.packID() == "test-pack")
    }

    @Test func notesForAVerseComeIntroductionFirstThenWidest() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        let notes = try repository.notes(for: VerseID(book: 43, chapter: 3, verse: 16))
        #expect(notes.map(\.id) == [2, 3, 1])
        #expect(notes.first?.range.isChapterIntroduction == true)
        #expect(try repository.notes(for: VerseID(book: 43, chapter: 3, verse: 22)).map(\.id) == [2])
    }

    @Test func readsTheBookIntroduction() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        #expect(try repository.introduction(toBook: 43)?.text == "The fourth Gospel.")
        #expect(try repository.introduction(toBook: 1) == nil)
    }

    @Test func listsArticlesLinkedToAVerse() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        #expect(try repository.articles(for: VerseID(book: 43, chapter: 3, verse: 6)).map(\.id) == ["kt/espiritu", "Nicodemus"])
        #expect(try repository.articles(for: VerseID(book: 43, chapter: 3, verse: 16)).map(\.id) == ["Nicodemus"])
        #expect(try repository.article(id: "kt/espiritu")?.title == "Espíritu")
    }

    @Test func searchesTitlesWithoutAccentsPrefixesFirst() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        #expect(try repository.searchArticles("ESPÍRITU").map(\.id) == ["kt/espiritu", "kt/santo"])
        #expect(try repository.searchArticles("50%").map(\.id) == ["pct"])
        // Wildcards are matched literally.
        #expect(try repository.searchArticles("%").map(\.id) == ["pct"])
        #expect(try repository.searchArticles("_").isEmpty)
        #expect(try repository.searchArticles("").count == 4)
    }

    @Test func looksUpLexiconsByPlainStrongsNumber() throws {
        let repository = try StudyResourceRepository(url: Self.makePack())
        let entries = try repository.lexicon(strongs: "h430")
        #expect(entries.map(\.source) == [.bdb])
        #expect(entries.first?.gloss == "God")
        #expect(try repository.lexicon(strongs: "H0430G").count == 1)
        #expect(try repository.lexicon(strongs: "not one").isEmpty)
    }
}

@Suite("Study library")
@MainActor
struct StudyResourceLibraryTests {
    @Test func hasItsOwnSwitchThatStartsOnForSavedChoices() throws {
        let defaults = try #require(UserDefaults(suiteName: "StudyLibrary-\(UUID())"))
        // A choice saved before the Study Library existed.
        let known = OptionalFeature.allCases.map(\.rawValue).filter { $0 != OptionalFeature.studyLibrary.rawValue }
        defaults.set(["prayer"], forKey: "features.enabled")
        defaults.set(known, forKey: "features.known")
        defaults.set(true, forKey: "features.chosen")
        let features = FeaturePreferences(defaults: defaults)
        #expect(features.isOn(.studyLibrary))
        #expect(!features.isOn(.plans), "Everything else stays as chosen")
        #expect(OptionalFeature.studyLibrary.area == .study)
        #expect(OptionalFeature.studyLibrary.legacyParent == nil)
        #expect(OptionalFeature.defaults.contains(.studyLibrary))
        #expect(OptionalFeature.studyLibrary.title != OptionalFeature.studyAssistant.title)
    }

    @Test func announcedOnce() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(ids.contains("study-library-notes-commentaries"))
        #expect(Set(ids).count == ids.count)
        #expect(WhatsNewCatalog.studyLibrary.feature == .studyLibrary)
        #expect(WhatsNewCatalog.studyLibrary.flag == nil)
    }
    @Test func startsEmptyAndForgetsMissingFiles() throws {
        let directory = URL.temporaryDirectory.appending(path: "StudyResources-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"resource":{"id":"gone","kind":"commentary","name":"Gone","license":"PD","file_url":"https://example.com/x","file_bytes":1,"database_bytes":1,"sha256":"a","version":1},"fileName":"gone-1.sqlite"}]"#
        try Data(json.utf8).write(to: directory.appending(path: "installed.json"))
        try Data().write(to: directory.appending(path: "old-1.sqlite"))
        let defaults = try #require(UserDefaults(suiteName: "study-\(UUID().uuidString)"))
        let library = StudyResourceLibrary(defaults: defaults, directory: directory)
        #expect(!library.hasAnyInstalled)
        #expect(library.repository("gone") == nil)
        // Files no edition points to are cleared away.
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "old-1.sqlite").path(percentEncoded: false)))
    }
}
