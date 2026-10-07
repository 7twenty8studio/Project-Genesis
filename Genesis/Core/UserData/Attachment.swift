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
/// never in SwiftData: it can be missing until it's downloaded, players and
/// viewers need a file URL, and a 25 MB PDF doesn't belong in the store.
/// Metadata syncs as public.attachments; the file goes to the private
/// `attachments` storage bucket (`AttachmentTransfers`).
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

/// Size and count rules for attachments.
enum AttachmentLimits {
    /// Photos are downscaled so the longer side is at most this many pixels.
    static let maxPhotoPixels = 2048
    static let jpegQuality: CGFloat = 0.75
    /// Voice recordings: AAC, mono, 64 kbps, at most two hours.
    static let audioBitRate = 64_000
    static let audioSampleRate = 44_100.0
    static let maxAudioDuration: TimeInterval = 2 * 60 * 60
    /// The storage bucket's limit, too.
    static let maxFileBytes = 25 * 1024 * 1024
    static let maxPDFBytes = maxFileBytes

    /// The most of one kind a prayer or sermon holds; 0 when it can't hold any.
    static func maximum(_ kind: AttachmentKind, for owner: AttachmentOwner) -> Int {
        guard owner.allowedKinds.contains(kind) else { return 0 }
        switch kind {
        case .photo: return 10
        case .audio: return 5
        case .pdf: return 3
        case .drawing: return 5
        }
    }

    /// How many more of `kind` fit, given the kinds already attached.
    static func remaining(_ kind: AttachmentKind, for owner: AttachmentOwner, existing: [AttachmentKind]) -> Int {
        max(0, maximum(kind, for: owner) - existing.filter { $0 == kind }.count)
    }

    static func canAdd(_ kind: AttachmentKind, to owner: AttachmentOwner, existing: [AttachmentKind]) -> Bool {
        remaining(kind, for: owner, existing: existing) > 0
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
        byteCount > 0 && byteCount <= (kind == .pdf ? maxPDFBytes : maxFileBytes)
    }
}

/// File names and cloud storage paths for attachments.
enum AttachmentPaths {
    /// The private storage bucket (20261014000000_attachments.sql).
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
