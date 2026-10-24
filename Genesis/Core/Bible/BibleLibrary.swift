import CryptoKit
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
    /// For a YouVersion Bible being built: how far along, 0...1 (books in
    /// hand of 66). Other downloads have no measured progress.
    private(set) var downloadProgress: [String: Double] = [:]
    /// Bumped when an unfinished download is kept or discarded, so the
    /// Bibles screen looks again at `savedBooks(for:)`.
    private(set) var pausedVersion = 0
    /// Bumped when a translation's text is replaced (a corrected edition), so
    /// the reader drops anything it cached from the old one.
    private(set) var editionVersion = 0
    var downloadError: String?
    /// YouVersion downloads under way, so iOS can stop one (ContinuedDownloads).
    @ObservationIgnored private var downloadJobs: [String: Task<Void, any Error>] = [:]

    /// Whether Premium Bibles (`Translation.requiresPremium`) can be read,
    /// set by RootView from the entitlement. Leaving Premium moves the reader
    /// to a free Bible in the same language; the download stays, so it
    /// opens again with Premium.
    var premiumBiblesUnlocked = true {
        didSet {
            if !premiumBiblesUnlocked, isLocked(currentTranslation) {
                currentTranslation = fallback(for: currentTranslation)
            }
        }
    }

    /// Shown to the server when downloading or updating a Premium Bible;
    /// RootView keeps the subscription in it, and the Bibles screen adds the
    /// account's token before a download.
    @ObservationIgnored var premiumProof: PremiumProof?

    /// A Premium Bible without Premium.
    func isLocked(_ translation: Translation) -> Bool {
        translation.requiresPremium && !premiumBiblesUnlocked
    }

    /// Another Bible to read instead of `translation`: one in the same
    /// language if there is one (the Reina-Valera for a Spanish Bible),
    /// else the KJV.
    func fallback(for translation: Translation) -> Translation {
        translations.first { $0.id != translation.id && $0.language == translation.language && !isLocked($0) } ?? .kjv
    }

    /// The Bible Premium tools read while `translation` is the reader's.
    /// YouVersion Platform Bibles are never shown in a paid feature (our
    /// agreement with YouVersion, LICENSED_BIBLES.md › 5), so Memorize,
    /// widgets, the morning welcome, word study and journal exports read a
    /// public-domain Bible in the same language instead. Every other Bible
    /// is used as it is.
    func premiumToolsTranslation(for translation: Translation) -> Translation {
        Self.premiumToolsTranslation(for: translation, among: translations)
    }

    /// The Bible Premium tools read now (see `premiumToolsTranslation(for:)`).
    var premiumToolsTranslation: Translation { premiumToolsTranslation(for: currentTranslation) }

    var premiumToolsRepository: BibleRepository { repository(for: premiumToolsTranslation) }

    /// The name of the Bible Premium tools will use with `translation`, for
    /// telling people before they choose it: the public-domain Bible in its
    /// language, even while that one is still to be downloaded (it comes
    /// along with a YouVersion Bible).
    func premiumToolsBibleName(for translation: Translation) -> String {
        let standIn = premiumToolsTranslation(for: translation)
        if standIn.language == translation.language { return standIn.name }
        return catalog.first { $0.youVersionID == nil && !$0.translation.isLicensed && !$0.premium && $0.language == translation.language }?.name ?? standIn.name
    }

    /// A public-domain Bible in the same language (the Reina-Valera for a
    /// Spanish Bible), else the KJV.
    nonisolated static func premiumToolsTranslation(for translation: Translation, among available: [Translation]) -> Translation {
        guard translation.isYouVersion else { return translation }
        return available.first { !$0.isLicensed && $0.language == translation.language } ?? .kjv
    }

    /// True when any Bible offered or downloaded is from the YouVersion
    /// Platform: its Terms ask apps that charge for anything to say the
    /// YouVersion Bible App is free (the Premium screen and Settings do).
    var offersYouVersionBibles: Bool {
        catalog.contains { $0.youVersionID != nil } || translations.contains(where: \.isYouVersion)
    }

    /// True when any Bible offered or downloaded needs Premium (so the
    /// Premium screen lists them only once there are some).
    var hasPremiumBibles: Bool {
        catalog.contains(where: \.premium) || translations.contains(where: \.requiresPremium)
    }

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
        Self.sealPlainDownloads(in: directory, installed: installed)
    }

    /// YouVersion Bibles built before they were sealed are sealed in place
    /// at once (they're also built again with footnotes on Wi-Fi), so no
    /// licensed text stays readable on the device.
    private static func sealPlainDownloads(in directory: URL, installed: [String: InstalledTranslation]) {
        for item in installed.values where item.translation.isYouVersion {
            let url = directory.appending(path: item.fileName)
            guard !BibleProtection.isSealed(fileAt: url), let data = try? Data(contentsOf: url) else { continue }
            try? BibleProtection.write(data, to: url)
        }
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
        } catch let error where installed[translation.id] != nil && !isBundled(translation) {
            CrashReporter.record(error, context: "BibleLibrary.repository")
            // A sealed Bible that will never open here (another device's
            // key) or a damaged file: forget it, so it can be downloaded
            // again. Locked away for now (before the phone's first unlock):
            // read another Bible this time and keep it.
            if error is CryptoKitError || error is SQLiteDatabase.Failure {
                remove(translation)
                let other = fallback(for: translation)
                return other.id == translation.id ? repository(for: .kjv) : repository(for: other)
            }
            // Kept: the bundled KJV this time (another locked Bible could
            // send this round in circles).
            return repository(for: .kjv)
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
    /// first (the Reina-Valera leads for someone using Versely in Spanish).
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
        withdrawEndedLicences(catalog: items)
        refreshInstalledDetails(catalog: items)
        for item in items where needsUpdate(item) {
            try? await install(item, allowsCellular: false)
        }
    }

    /// A licensed Bible stays on the device only while Versely may offer
    /// it: when its row is gone from the catalog (the licence ended, or the
    /// owner turned it off) the download is removed. Only after a catalog
    /// that loaded; offline, nothing changes.
    private func withdrawEndedLicences(catalog items: [DownloadableTranslation]) {
        guard !items.isEmpty else { return }
        let offered = Set(items.map(\.id))
        for item in installed.values where item.translation.isLicensed && !offered.contains(item.translation.id) {
            remove(item.translation)
        }
    }

    /// Keeps a downloaded Bible's details (copyright wording, whether it
    /// needs Premium) as the catalog has them, without downloading again.
    private func refreshInstalledDetails(catalog items: [DownloadableTranslation]) {
        var changed = false
        for item in items {
            guard let current = installed[item.id], current.translation != item.translation else { continue }
            installed[item.id] = InstalledTranslation(translation: item.translation, version: current.version, fileName: current.fileName, installedAt: current.installedAt, format: current.format)
            changed = true
        }
        guard changed else { return }
        saveInstalled()
        translations = Self.merge(installed: installed)
        if let updated = translations.first(where: { $0.id == currentTranslation.id }), updated != currentTranslation {
            currentTranslation = updated
        }
        if isLocked(currentTranslation) { currentTranslation = fallback(for: currentTranslation) }
    }

    private func needsUpdate(_ item: DownloadableTranslation, now: Date = .now) -> Bool {
        if let current = installed[item.id] {
            if item.version > current.version { return true }
            // A YouVersion Bible built before footnotes and sealing is
            // built again. Otherwise each chapter is refreshed when it's
            // opened online after its lifetime (`refreshIfStale`).
            if item.youVersionID != nil {
                return (current.format ?? 1) < YouVersionBibleBuilder.format
            }
            return false
        }
        return isBundled(item.translation) && item.version > Self.bundledVersion
    }

    func download(_ item: DownloadableTranslation) async {
        downloadError = nil
        guard item.youVersionID != nil else {
            do {
                try await install(item, allowsCellular: true)
            } catch {
                downloadError = error.localizedDescription
            }
            return
        }
        guard !downloading.contains(item.id) else { return }
        // A YouVersion Bible takes minutes: it carries on after the person
        // leaves Versely (ContinuedDownloads), and stops cleanly, keeping
        // its books, if they stop it from iOS's progress or the time ends.
        let id = item.id
        let job = Task { @MainActor in try await self.install(item, allowsCellular: true) }
        downloadJobs[id] = job
        let continued = ContinuedDownloads.shared
        continued.onExpire = { [weak self] expired in self?.downloadJobs[expired]?.cancel() }
        continued.begin(id: id, title: item.translation.name, books: YouVersionBibleBuilder.savedBookCount(for: item, in: directory), of: YouVersionBibleBuilder.bookCodes.count)
        var finished = false
        do {
            try await job.value
            finished = true
            // Lockman asks each year how many copies were distributed: an
            // anonymous count of finished downloads (rebuilds aren't counted).
            await downloader.recordDownload(item)
            await installPremiumToolsBible(for: item, allowsCellular: true)
        } catch is CancellationError {
            // Stopped from iOS's progress (or its time ran out): paused,
            // with what it has, ready to continue.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            downloadError = error.localizedDescription
        }
        downloadJobs[id] = nil
        continued.end(id: id, success: finished)
    }

    private func install(_ item: DownloadableTranslation, allowsCellular: Bool) async throws {
        guard !downloading.contains(item.id) else { return }
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        // A new file per edition: the old one may still be open for reading.
        // A YouVersion Bible is rebuilt within an edition, so its name also
        // carries the time it was built.
        let now = Date.now
        let fileName = item.youVersionID == nil
            ? "\(item.id)-\(item.version).sqlite"
            : "\(item.id)-\(item.version)-\(Int(now.timeIntervalSince1970)).sqlite"
        defer {
            downloadProgress[item.id] = nil
            pausedVersion += 1
        }
        let id = item.id
        let total = Double(YouVersionBibleBuilder.bookCodes.count)
        try await downloader.download(item, to: directory.appending(path: fileName), allowsCellular: allowsCellular, proof: premiumProof) { books in
            Task { @MainActor in
                guard self.downloading.contains(id) else { return }
                self.downloadProgress[id] = Double(books) / total
                ContinuedDownloads.shared.update(id: id, books: books)
            }
        }
        installed[item.id] = InstalledTranslation(
            translation: item.translation, version: item.version, fileName: fileName, installedAt: now,
            format: item.youVersionID != nil ? YouVersionBibleBuilder.format : nil
        )
        saveInstalled()
        repositories[item.id] = nil
        translations = Self.merge(installed: installed)
        if currentTranslation.id == item.id { currentTranslation = item.translation }
        editionVersion += 1
    }

    /// Premium tools read a public-domain Bible in the same language as a
    /// YouVersion Bible; for a Spanish one that's the Reina-Valera, which is
    /// a download, so it comes along (quietly, if it can).
    private func installPremiumToolsBible(for item: DownloadableTranslation, allowsCellular: Bool) async {
        guard item.youVersionID != nil,
              !translations.contains(where: { !$0.isLicensed && $0.language == item.language }),
              let standIn = catalog.first(where: { $0.youVersionID == nil && !$0.translation.isLicensed && !$0.premium && $0.language == item.language })
        else { return }
        try? await install(standIn, allowsCellular: allowsCellular)
    }

    /// Books an unfinished YouVersion download already has (0 if none):
    /// the Bibles screen offers to continue it.
    func savedBooks(for item: DownloadableTranslation) -> Int {
        _ = pausedVersion
        guard item.youVersionID != nil, !downloading.contains(item.id) else { return 0 }
        return YouVersionBibleBuilder.savedBookCount(for: item, in: directory)
    }

    /// Forgets an unfinished YouVersion download.
    func discardDownload(_ item: DownloadableTranslation) {
        YouVersionBibleBuilder.discard(item, in: directory)
        pausedVersion += 1
    }

    func remove(_ translation: Translation) {
        guard isRemovable(translation), let item = installed[translation.id] else { return }
        if currentTranslation.id == translation.id {
            currentTranslation = fallback(for: translation)
        }
        installed[translation.id] = nil
        saveInstalled()
        repositories[translation.id] = nil
        translations = Self.merge(installed: installed)
        try? FileManager.default.removeItem(at: directory.appending(path: item.fileName))
        YouVersionFreshness.remove(for: translation.id, in: directory)
    }

    // MARK: Refreshing YouVersion chapters

    @ObservationIgnored private var refreshing: Set<String> = []

    /// A YouVersion Bible's chapter, opened while online after the
    /// Platform's Cache-Control lifetime, is fetched again (through our
    /// shared cache) and the stored Bible updated if the publisher changed
    /// it; YouVersion confirmed that following the header complies. The
    /// stored chapter shows meanwhile; offline, or if the Platform is busy,
    /// nothing changes and it's tried again next time.
    func refreshIfStale(_ chapter: ChapterID, of translation: Translation) {
        guard translation.isYouVersion, let item = installed[translation.id], let client = downloader.client,
              !downloading.contains(translation.id) else { return }
        let key = "\(translation.id) \(chapter.book).\(chapter.chapter)"
        guard !refreshing.contains(key),
              YouVersionFreshness.load(for: translation.id, in: directory).isStale(book: chapter.book, chapter: chapter.chapter) else { return }
        refreshing.insert(key)
        let folder = directory
        let stored = self.repository(for: translation)
        Task {
            defer { self.refreshing.remove(key) }
            guard let fresh = try? await YouVersionBibleBuilder(client: client).fetchChapter(id: translation.id, book: chapter.book, chapter: chapter.chapter) else { return }
            let fetchedAt = Date.now
            let url = folder.appending(path: item.fileName)
            let changed = await Task.detached(priority: .utility) { () -> Bool in
                guard let current = try? stored.chapter(chapter),
                      YouVersionChapterComparison.differs(stored: current, fresh: fresh) else { return false }
                guard let data = try? BibleProtection.read(url),
                      let patched = try? BibleFileWriter.replacingChapter(fresh, book: chapter.book, in: data),
                      (try? BibleProtection.write(patched, to: url)) != nil else { return false }
                return true
            }.value
            // Loaded again just before saving, so chapters refreshed at the
            // same time don't overwrite each other's times.
            var freshness = YouVersionFreshness.load(for: translation.id, in: folder)
            freshness.set(book: chapter.book, chapter: chapter.chapter, fetchedAt: fetchedAt, maxAge: fresh.maxAge)
            freshness.save(for: translation.id, in: folder)
            // Re-read only if this edition is still the one installed.
            if changed, self.installed[translation.id]?.fileName == item.fileName {
                self.repositories[translation.id] = nil
                self.editionVersion += 1
            }
        }
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
        // (".partial": a YouVersion Bible whose build was cut short.)
        for file in files where (file.hasSuffix(".sqlite") && !keep.contains(file)) || file.hasSuffix(".partial") {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }
}
