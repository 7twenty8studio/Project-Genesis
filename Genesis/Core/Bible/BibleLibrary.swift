import Foundation
import Observation

/// Owns the offline Bible databases and the reader's chosen translation.
///
/// Bundled translations (KJV, WEB, ASV) ship inside the app. More can be
/// downloaded from the catalog in Supabase; they live in Application
/// Support/Bibles. A download of a bundled translation (a corrected edition)
/// is used in place of the bundled copy.
@MainActor
@Observable
final class BibleLibrary {
    private(set) var translations: [Translation]
    /// What's offered for download, from the server (empty offline).
    private(set) var catalog: [DownloadableTranslation] = []
    /// Download progress, by translation id (indeterminate while running).
    private(set) var downloading: Set<String> = []
    /// Bumped when a translation's text is replaced (a corrected edition), so
    /// the reader drops anything it cached from the old one.
    private(set) var editionVersion = 0
    var downloadError: String?

    var currentTranslation: Translation {
        didSet { defaults.set(currentTranslation.id, forKey: Self.translationKey) }
    }

    @ObservationIgnored private var repositories: [String: BibleRepository] = [:]
    @ObservationIgnored private var installed: [String: InstalledTranslation]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var downloader: TranslationDownloader
    /// Nil only if the bundled cross-reference database is missing.
    @ObservationIgnored let crossReferences: CrossReferenceRepository?

    private static let translationKey = "library.currentTranslation"
    /// Bundled databases are edition 1; a catalog row with a higher version replaces them.
    private static let bundledVersion = 1

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        directory: URL = BibleLibrary.downloadsDirectory,
        downloader: TranslationDownloader = TranslationDownloader(client: nil)
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.directory = directory
        self.downloader = downloader
        let installed = Self.loadInstalled(from: directory)
        self.installed = installed
        let all = Self.merge(installed: installed)
        translations = all
        let savedID = defaults.string(forKey: Self.translationKey)
        currentTranslation = all.first { $0.id == savedID } ?? .kjv
        crossReferences = bundle.url(forResource: "CrossReferences", withExtension: "sqlite")
            .flatMap { try? CrossReferenceRepository(url: $0) }
        Self.removeLeftovers(in: directory, keeping: installed)
    }

    /// True once the person has picked a translation during onboarding.
    var hasChosenTranslation: Bool {
        defaults.string(forKey: Self.translationKey) != nil
    }

    var current: BibleRepository { repository(for: currentTranslation) }

    func repository(for translation: Translation) -> BibleRepository {
        if let cached = repositories[translation.id] { return cached }
        guard let url = databaseURL(for: translation) else {
            preconditionFailure("\(translation.id).sqlite is missing from the app bundle.")
        }
        do {
            let repository = try BibleRepository(translation: translation, url: url)
            repositories[translation.id] = repository
            return repository
        } catch {
            preconditionFailure("Could not open \(translation.id): \(error)")
        }
    }

    /// Where a translation's database lives: a download if present, else the bundle.
    func databaseURL(for translation: Translation) -> URL? {
        if let item = installed[translation.id] {
            let url = directory.appending(path: item.fileName)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        }
        return bundle.url(forResource: translation.id, withExtension: "sqlite")
    }

    func isAvailableOffline(_ translation: Translation) -> Bool {
        databaseURL(for: translation) != nil
    }

    func isBundled(_ translation: Translation) -> Bool {
        Translation.bundled.contains { $0.id == translation.id }
    }

    /// Downloaded (not bundled) translations can be removed.
    func isRemovable(_ translation: Translation) -> Bool {
        !isBundled(translation) && installed[translation.id] != nil
    }

    /// Catalog entries not yet on this device, those in the app's language
    /// first (the Reina-Valera leads for someone using Genesis in Spanish).
    var available: [DownloadableTranslation] {
        let missing = catalog.filter { item in !translations.contains { $0.id == item.id } }
        return missing.filter { $0.language == AppLanguage.code } + missing.filter { $0.language != AppLanguage.code }
    }

    nonisolated static var downloadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Bibles", directoryHint: .isDirectory)
    }

    // MARK: Downloads

    func setDownloader(_ downloader: TranslationDownloader) {
        self.downloader = downloader
    }

    /// Fetches the catalog and quietly brings downloaded (or bundled)
    /// translations up to date on Wi-Fi.
    func refreshCatalog() async {
        guard let items = try? await downloader.catalog() else { return }
        catalog = items
        for item in items where needsUpdate(item) {
            try? await install(item, allowsCellular: false)
        }
    }

    private func needsUpdate(_ item: DownloadableTranslation) -> Bool {
        if let current = installed[item.id] { return item.version > current.version }
        return isBundled(item.translation) && item.version > Self.bundledVersion
    }

    func download(_ item: DownloadableTranslation) async {
        downloadError = nil
        do {
            try await install(item, allowsCellular: true)
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func install(_ item: DownloadableTranslation, allowsCellular: Bool) async throws {
        guard !downloading.contains(item.id) else { return }
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        // A new file per edition: the old one may still be open for reading.
        let fileName = "\(item.id)-\(item.version).sqlite"
        try await downloader.download(item, to: directory.appending(path: fileName), allowsCellular: allowsCellular)
        installed[item.id] = InstalledTranslation(translation: item.translation, version: item.version, fileName: fileName)
        saveInstalled()
        repositories[item.id] = nil
        translations = Self.merge(installed: installed)
        if currentTranslation.id == item.id { currentTranslation = item.translation }
        editionVersion += 1
    }

    func remove(_ translation: Translation) {
        guard isRemovable(translation), let item = installed[translation.id] else { return }
        if currentTranslation.id == translation.id { currentTranslation = .kjv }
        installed[translation.id] = nil
        saveInstalled()
        repositories[translation.id] = nil
        translations = Self.merge(installed: installed)
        try? FileManager.default.removeItem(at: directory.appending(path: item.fileName))
    }

    // MARK: Storage

    private static func merge(installed: [String: InstalledTranslation]) -> [Translation] {
        let bundled = Translation.bundled.map { installed[$0.id]?.translation ?? $0 }
        let extra = installed.values
            .filter { item in !Translation.bundled.contains { $0.id == item.translation.id } }
            .map(\.translation)
            .sorted { $0.name < $1.name }
        return bundled + extra
    }

    private static func loadInstalled(from directory: URL) -> [String: InstalledTranslation] {
        guard let data = try? Data(contentsOf: directory.appending(path: "installed.json")),
              let items = try? JSONDecoder().decode([InstalledTranslation].self, from: data) else { return [:] }
        // Downloads aren't in iCloud backups, so after a restore the list can
        // name files that are gone: forget those (they can be downloaded again).
        let present = items.filter { item in
            FileManager.default.fileExists(atPath: directory.appending(path: item.fileName).path(percentEncoded: false))
        }
        return Dictionary(present.map { ($0.translation.id, $0) }, uniquingKeysWith: { $0.version >= $1.version ? $0 : $1 })
    }

    private func saveInstalled() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let items = installed.values.sorted { $0.translation.id < $1.translation.id }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: directory.appending(path: "installed.json"), options: .atomic)
        }
    }

    /// Old editions replaced by an update are deleted on the next launch,
    /// once nothing has them open.
    private static func removeLeftovers(in directory: URL, keeping installed: [String: InstalledTranslation]) {
        let keep = Set(installed.values.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for file in files where file.hasSuffix(".sqlite") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }
}
