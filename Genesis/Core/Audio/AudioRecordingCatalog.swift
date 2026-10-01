import Foundation

/// A recorded human narration of one translation (public.audio_recordings).
/// Recordings are listed in Supabase, so new ones can be added, moved to
/// another host or withdrawn without an app update.
struct AudioRecording: Identifiable, Hashable, Codable, Sendable {
    let id: String
    /// The translation id it narrates ("WEB").
    let translation: String
    /// Usually the narrator ("Basil Sands").
    let title: String
    let description: String
    /// Shown with the recording, e.g. "Public domain".
    let license: String
    let sourceURL: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, translation, title, description, license
        case sourceURL = "source_url"
        case updatedAt = "updated_at"
    }
}

enum AudioRecordingError: LocalizedError, Equatable {
    case notConfigured
    case chapterMissing
    case offline

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Recorded narration isn't available in this build."
        case .chapterMissing: "This recording doesn't include this chapter."
        case .offline: "Recorded narration needs an internet connection, or download the book first."
        }
    }
}

/// The recordings on offer, where each chapter's file lives, and books
/// downloaded for offline listening.
@MainActor
@Observable
final class AudioRecordingCatalog {
    private(set) var recordings: [AudioRecording]
    /// Download progress per book key (`recordingID/book`), 0...1.
    private(set) var downloads: [String: Double] = [:]
    /// Bumped when downloads are added or removed.
    private(set) var storageVersion = 0

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var chapterMaps: [String: [String: URL]] = [:]

    init(client: SupabaseClient?, directory: URL = AudioRecordingCatalog.defaultDirectory) {
        self.client = client
        self.directory = directory
        let saved = try? Data(contentsOf: directory.appending(path: "catalog.json"))
        recordings = saved.flatMap { try? JSONDecoder().decode([AudioRecording].self, from: $0) } ?? []
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Audio", directoryHint: .isDirectory)
    }

    func recordings(for translation: Translation) -> [AudioRecording] {
        recordings.filter { $0.translation == translation.id }
    }

    func recording(id: String) -> AudioRecording? {
        recordings.first { $0.id == id }
    }

    /// Asks the server which recordings are available; keeps the last list offline.
    func refresh() async {
        guard let client else { return }
        let query = [
            URLQueryItem(name: "select", value: "id,translation,title,description,license,source_url,updated_at"),
            URLQueryItem(name: "enabled", value: "eq.true"),
            URLQueryItem(name: "order", value: "sort.asc"),
        ]
        guard let rows = try? await client.select("audio_recordings", query: query, as: AudioRecording.self) else { return }
        if rows != recordings {
            recordings = rows
            chapterMaps.removeAll()
        }
        save(try? JSONEncoder().encode(rows), to: directory.appending(path: "catalog.json"))
    }

    // MARK: Chapters

    /// Where to play a chapter from: the downloaded file if there is one,
    /// otherwise the recording's online file.
    func url(for chapter: ChapterID, in recording: AudioRecording) async throws -> URL {
        let remote = try await chapterURLs(for: recording)[Self.key(chapter)]
        guard let remote else { throw AudioRecordingError.chapterMissing }
        let local = localURL(for: chapter, in: recording, remote: remote)
        return FileManager.default.fileExists(atPath: local.path) ? local : remote
    }

    private func chapterURLs(for recording: AudioRecording) async throws -> [String: URL] {
        let cacheKey = "\(recording.id)@\(recording.updatedAt)"
        if let cached = chapterMaps[cacheKey] { return cached }
        let file = directory.appending(path: "\(recording.id)/chapters-\(Self.safe(recording.updatedAt)).json")
        if let data = try? Data(contentsOf: file), let map = try? JSONDecoder().decode([String: URL].self, from: data) {
            chapterMaps[cacheKey] = map
            return map
        }
        guard let client else { throw AudioRecordingError.notConfigured }
        struct Row: Decodable, Sendable { let chapter_urls: [String: String] }
        let rows: [Row]
        do {
            rows = try await client.select("audio_recordings", query: [
                URLQueryItem(name: "select", value: "chapter_urls"),
                URLQueryItem(name: "id", value: "eq.\(recording.id)"),
            ])
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw AudioRecordingError.offline
        }
        let map = (rows.first?.chapter_urls ?? [:]).compactMapValues { string -> URL? in
            guard let url = URL(string: string), url.scheme == "https" else { return nil }
            return url
        }
        chapterMaps[cacheKey] = map
        save(try? JSONEncoder().encode(map), to: file)
        return map
    }

    /// "43.3" for John 3.
    nonisolated static func key(_ chapter: ChapterID) -> String {
        "\(chapter.book).\(chapter.chapter)"
    }

    // MARK: Downloads

    private func bookDirectory(_ book: Int, in recording: AudioRecording) -> URL {
        directory.appending(path: "\(recording.id)/\(book)", directoryHint: .isDirectory)
    }

    private func localURL(for chapter: ChapterID, in recording: AudioRecording, remote: URL) -> URL {
        let ext = remote.pathExtension.isEmpty ? "mp3" : remote.pathExtension
        return bookDirectory(chapter.book, in: recording).appending(path: "\(chapter.chapter).\(ext)")
    }

    func downloadKey(_ book: BibleBook, in recording: AudioRecording) -> String {
        "\(recording.id)/\(book.id)"
    }

    /// True when every chapter of the book is on this device.
    func isDownloaded(_ book: BibleBook, in recording: AudioRecording) -> Bool {
        _ = storageVersion
        let folder = bookDirectory(book.id, in: recording)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { !$0.hasPrefix(".") }.count >= book.chapterCount
    }

    /// Downloads a book's chapters for offline listening.
    func download(_ book: BibleBook, in recording: AudioRecording) async throws {
        let key = downloadKey(book, in: recording)
        guard downloads[key] == nil else { return }
        downloads[key] = 0
        defer { downloads[key] = nil; storageVersion += 1 }
        let map = try await chapterURLs(for: recording)
        let folder = bookDirectory(book.id, in: recording)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var root = directory
        try? root.setResourceValues(excluded)

        for number in 1...book.chapterCount {
            try Task.checkCancellation()
            let chapter = ChapterID(book: book.id, chapter: number)
            guard let remote = map[Self.key(chapter)] else { continue }
            let destination = localURL(for: chapter, in: recording, remote: remote)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let (temporary, response) = try await URLSession.shared.download(from: remote)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw AudioRecordingError.chapterMissing
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            downloads[key] = Double(number) / Double(book.chapterCount)
        }
    }

    func removeDownload(_ book: BibleBook, in recording: AudioRecording) {
        try? FileManager.default.removeItem(at: bookDirectory(book.id, in: recording))
        storageVersion += 1
    }

    /// Space used by downloaded narration, in bytes.
    func downloadedBytes() -> Int64 {
        _ = storageVersion
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator where url.pathExtension != "json" {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: Helpers

    private func save(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func safe(_ string: String) -> String {
        String(string.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }
}
