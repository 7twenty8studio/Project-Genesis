import CoreGraphics
import Foundation
import SwiftData

/// What an attachment belongs to.
enum AttachmentOwner: String, Codable, CaseIterable, Sendable {
    case prayer, sermon

    /// The kinds this owner can hold: PDFs and Pencil pages are for sermons.
    var allowedKinds: [AttachmentKind] {
        switch self {
        case .prayer: [.photo, .audio]
        case .sermon: [.photo, .audio, .pdf, .drawing]
        }
    }
}

/// The kind of file an attachment holds.
enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case photo, audio, pdf, drawing

    /// The file's extension, locally and in cloud storage.
    var fileExtension: String {
        switch self {
        case .photo: "jpg"
        case .audio: "m4a"
        case .pdf: "pdf"
        case .drawing: "drawing"
        }
    }

    /// The MIME type sent to the `attachments` storage bucket (which allows
    /// exactly these, see 20261014000000_attachments.sql).
    var contentType: String {
        switch self {
        case .photo: "image/jpeg"
        case .audio: "audio/mp4"
        case .pdf: "application/pdf"
        case .drawing: "application/octet-stream"
        }
    }

    var title: String {
        switch self {
        case .photo: String(localized: "Photo", comment: "Attachment kind")
        case .audio: String(localized: "Voice Recording", comment: "Attachment kind")
        case .pdf: String(localized: "PDF", comment: "Attachment kind")
        case .drawing: String(localized: "Drawing", comment: "Attachment kind: an Apple Pencil page")
        }
    }

    var systemImage: String {
        switch self {
        case .photo: "photo"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .drawing: "pencil.tip.crop.circle"
        }
    }
}

/// A photo, voice recording, PDF or Pencil page on a prayer or sermon
/// (Premium, `.journalExtras`).
///
/// The file itself lives in Application Support/Attachments (`AttachmentFiles`),
/// never in SwiftData: it can be missing until it's downloaded, and players
/// and viewers need a file URL.
/// Metadata syncs as public.attachments; the file goes to the person's own
/// iCloud (`ICloudAttachmentStorage`, through `AttachmentTransfers`).
@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var ownerKindRaw: String
    var ownerID: UUID
    var kindRaw: String
    var byteSize: Int = 0
    /// Seconds, for voice recordings.
    var duration: Double? = nil
    /// Pages, for PDFs.
    var pageCount: Int? = nil
    var caption: String = ""
    var sortOrder: Int = 0
    /// Local only, never synced: the file still has to go up to cloud storage.
    var needsUpload: Bool = true
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), owner: AttachmentOwner, ownerID: UUID, kind: AttachmentKind, date: Date = .now) {
        self.id = id
        ownerKindRaw = owner.rawValue
        self.ownerID = ownerID
        kindRaw = kind.rawValue
        createdAt = date
        updatedAt = date
    }

    var owner: AttachmentOwner { AttachmentOwner(rawValue: ownerKindRaw) ?? .prayer }
    var kind: AttachmentKind { AttachmentKind(rawValue: kindRaw) ?? .photo }

    /// "<id>.jpg": the name of the local file and of the object in storage.
    var fileName: String { AttachmentPaths.fileName(id: id, kind: kind) }
}

/// Size rules for attachments. There's no count limit: files live on the
/// person's device and in their own iCloud, not in Genesis's storage.
enum AttachmentLimits {
    /// Photos are downscaled so the longer side is at most this many pixels
    /// (about 200–400 KB each), which keeps the person's iCloud and syncing light.
    static let maxPhotoPixels = 1600
    static let jpegQuality: CGFloat = 0.7
    /// Voice recordings: AAC, mono, 32 kbps at 22.05 kHz (clear for speech,
    /// about 14 MB an hour). The recorder stops itself after 4 hours, in
    /// case it's left running.
    static let audioBitRate = 32_000
    static let audioSampleRate = 22_050.0
    static let maxAudioDuration: TimeInterval = 4 * 60 * 60
    /// One file at most; CloudKit takes assets up to 250 MB.
    static let maxFileBytes = 250 * 1024 * 1024

    static func canAdd(_ kind: AttachmentKind, to owner: AttachmentOwner) -> Bool {
        owner.allowedKinds.contains(kind)
    }

    /// The pixel size a photo is stored at: the longer side at most
    /// `maxPixels`, the shape kept, never enlarged, each side at least 1.
    static func scaledPixelSize(_ size: CGSize, maxPixels: Int = maxPhotoPixels) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > CGFloat(maxPixels), size.width > 0, size.height > 0 else {
            return CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
        }
        let scale = CGFloat(maxPixels) / longest
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// True when a file of this size may be kept and synced.
    static func fits(byteCount: Int, kind: AttachmentKind) -> Bool {
        byteCount > 0 && byteCount <= maxFileBytes
    }
}

/// File names and cloud storage paths for attachments.
enum AttachmentPaths {
    /// The private storage bucket earlier versions used (20261014000000_attachments.sql);
    /// files now go to iCloud, and ones left here move there.
    static let bucket = "attachments"

    /// "<attachment id>.<ext>", lowercased like the server's ids.
    static func fileName(id: UUID, kind: AttachmentKind) -> String {
        "\(id.uuidString.lowercased()).\(kind.fileExtension)"
    }

    /// "<user id>/<attachment id>.<ext>". The first folder must be the
    /// account's id (`auth.uid()::text`, lowercase): the bucket's policies
    /// allow each person only their own folder.
    static func storagePath(userID: UUID, fileName: String) -> String {
        "\(userID.uuidString.lowercased())/\(fileName)"
    }

    static func storagePath(userID: UUID, id: UUID, kind: AttachmentKind) -> String {
        storagePath(userID: userID, fileName: fileName(id: id, kind: kind))
    }
}
