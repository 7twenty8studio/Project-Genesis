import Foundation
import Observation

/// The study packs on this device (study notes, commentaries, Bible
/// dictionaries, lexicons) and those offered for download. Every pack is an
/// optional download, kept in Application Support/StudyResources and
/// updated on Wi-Fi when a corrected edition comes out. Premium packs
/// (`DownloadableStudyResource.premium`) need `.wordStudy` to download and
/// read; the views check it.
@MainActor
@Observable
final class StudyResourceLibrary {
    /// What's offered for download, from the server (empty offline).
    private(set) var catalog: [DownloadableStudyResource] = []
    private(set) var installed: [String: InstalledStudyResource]
    /// Pack ids being downloaded.
    private(set) var downloading: Set<String> = []
    var downloadError: String?

    /// The commentary chosen beside a verse.
    var chosenCommentaryID: String? {
        didSet { defaults.set(chosenCommentaryID, forKey: Self.commentaryKey) }
    }

    @ObservationIgnored private var repositories: [String: StudyResourceRepository] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var downloader: StudyResourceDownloader

    private static let commentaryKey = "studyResources.commentary"

    init(
        defaults: UserDefaults = .standard,
        directory: URL = StudyResourceLibrary.downloadsDirectory,
        downloader: StudyResourceDownloader = StudyResourceDownloader(client: nil)
    ) {
        self.defaults = defaults
        self.directory = directory
        self.downloader = downloader
        let installed = Self.loadInstalled(from: directory)
        self.installed = installed
        chosenCommentaryID = defaults.string(forKey: Self.commentaryKey)
        Self.removeLeftovers(in: directory, keeping: installed)
    }

    nonisolated static var downloadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "StudyResources", directoryHint: .isDirectory)
    }

    // MARK: What's here

    /// Installed packs of a kind, in the catalog's order (sort, then name).
    func installedResources(_ kind: StudyResourceKind) -> [DownloadableStudyResource] {
        installed.values.map(\.resource)
            .filter { $0.kind == kind }
            .sorted { ($0.sortOrder(in: catalog), $0.name) < ($1.sortOrder(in: catalog), $1.name) }
    }

    func isInstalled(_ id: String) -> Bool {
        installed[id] != nil
    }

    var hasAnyInstalled: Bool { !installed.isEmpty }

    /// Everything offered, installed or not, in the catalog's order, with
    /// installed packs the server no longer lists kept at the end.
    var all: [DownloadableStudyResource] {
        let listed = Set(catalog.map(\.id))
        let extra = installed.values.map(\.resource).filter { !listed.contains($0.id) }.sorted { $0.name < $1.name }
        return catalog + extra
    }

    /// The commentary to show beside a verse: the one chosen, else the first installed.
    func commentary(allowsPremium: Bool) -> DownloadableStudyResource? {
        let commentaries = installedResources(.commentary).filter { allowsPremium || !$0.premium }
        return commentaries.first { $0.id == chosenCommentaryID } ?? commentaries.first
    }

    func resource(_ id: String) -> DownloadableStudyResource? {
        installed[id]?.resource ?? catalog.first { $0.id == id }
    }

    /// The pack's database, opened once; nil if it isn't installed.
    func repository(_ id: String) -> StudyResourceRepository? {
        if let cached = repositories[id] { return cached }
        guard let item = installed[id] else { return nil }
        guard let repository = try? StudyResourceRepository(url: directory.appending(path: item.fileName)) else { return nil }
        repositories[id] = repository
        return repository
    }

    // MARK: Downloads

    func setDownloader(_ downloader: StudyResourceDownloader) {
        self.downloader = downloader
    }

    /// Fetches the catalog and quietly brings downloaded packs up to date on Wi-Fi.
    func refreshCatalog() async {
        guard let items = try? await downloader.catalog() else { return }
        catalog = items
        for item in items {
            guard let current = installed[item.id] else { continue }
            if item.version > current.resource.version {
                try? await install(item, allowsCellular: false)
            } else if item.version == current.resource.version {
                // Same edition: keep the server's latest name and attribution.
                installed[item.id] = InstalledStudyResource(resource: item, fileName: current.fileName)
            }
        }
        saveInstalled()
    }

    func download(_ item: DownloadableStudyResource) async {
        downloadError = nil
        do {
            try await install(item, allowsCellular: true)
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func install(_ item: DownloadableStudyResource, allowsCellular: Bool) async throws {
        guard !downloading.contains(item.id) else { return }
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        // A new file per edition: the old one may still be open for reading.
        let fileName = "\(item.id)-\(item.version).sqlite"
        try await downloader.download(item, to: directory.appending(path: fileName), allowsCellular: allowsCellular)
        installed[item.id] = InstalledStudyResource(resource: item, fileName: fileName)
        repositories[item.id] = nil
        saveInstalled()
    }

    func remove(_ id: String) {
        guard let item = installed[id] else { return }
        installed[id] = nil
        repositories[id] = nil
        if chosenCommentaryID == id { chosenCommentaryID = nil }
        saveInstalled()
        try? FileManager.default.removeItem(at: directory.appending(path: item.fileName))
    }

    // MARK: Storage

    private static func loadInstalled(from directory: URL) -> [String: InstalledStudyResource] {
        guard let data = try? Data(contentsOf: directory.appending(path: "installed.json")),
              let items = try? JSONDecoder().decode([InstalledStudyResource].self, from: data) else { return [:] }
        // Downloads aren't in iCloud backups: forget files that are gone.
        let present = items.filter { item in
            FileManager.default.fileExists(atPath: directory.appending(path: item.fileName).path(percentEncoded: false))
        }
        return Dictionary(present.map { ($0.resource.id, $0) }, uniquingKeysWith: { $0.resource.version >= $1.resource.version ? $0 : $1 })
    }

    private func saveInstalled() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let items = installed.values.sorted { $0.resource.id < $1.resource.id }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: directory.appending(path: "installed.json"), options: .atomic)
        }
    }

    /// Old editions replaced by an update are deleted on the next launch.
    private static func removeLeftovers(in directory: URL, keeping installed: [String: InstalledStudyResource]) {
        let keep = Set(installed.values.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for file in files where file.hasSuffix(".sqlite") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }
}

private extension DownloadableStudyResource {
    func sortOrder(in catalog: [DownloadableStudyResource]) -> Int {
        catalog.firstIndex { $0.id == id } ?? Int.max
    }
}
