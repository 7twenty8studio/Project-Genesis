import Foundation

/// Attachment files on this device: Application Support/Attachments, one
/// file per attachment named "<id>.<ext>". A synced attachment's file may be
/// missing until it's downloaded (`AttachmentTransfers.ensureFile`).
struct AttachmentFiles: Sendable {
    let directory: URL

    /// Application Support/Attachments (backed up with the app's data).
    static var standard: AttachmentFiles {
        let base = URL.applicationSupportDirectory
        return AttachmentFiles(directory: base.appending(path: "Attachments", directoryHint: .isDirectory))
    }

    /// A fresh folder for UI tests, so no run sees another's files.
    static func temporary() -> AttachmentFiles {
        AttachmentFiles(directory: URL.temporaryDirectory.appending(path: "Attachments-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path(percentEncoded: false))
    }

    func write(_ data: Data, to fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Moves a finished file (e.g. a recording) into place.
    func move(_ source: URL, to fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: fileName)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func read(_ fileName: String) throws -> Data {
        try Data(contentsOf: url(for: fileName))
    }

    func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Every attachment file on this device (signing out with "remove data").
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A scratch file in the same folder, for a recording in progress.
    func scratchURL(extension fileExtension: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "scratch-\(UUID().uuidString.lowercased()).\(fileExtension)", directoryHint: .notDirectory)
    }
}
