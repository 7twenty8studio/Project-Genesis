import Foundation
import SwiftData

// Attachments on prayers and sermons (Premium). Same rules as the rest of
// StudyStore: every change updates `updatedAt`, deletions leave a tombstone
// for sync. The file is written by the caller (`AttachmentFiles`) before the
// record is added; deleting the record discards the file too.

extension StudyStore {
    /// An owner's attachments in their order.
    func attachments(for owner: AttachmentOwner, id ownerID: UUID) -> [Attachment] {
        let kind = owner.rawValue
        let key = ownerID
        let descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.ownerID == key && $0.ownerKindRaw == kind },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// True when the owner can hold attachments of `kind`.
    func canAttach(_ kind: AttachmentKind, to owner: AttachmentOwner, id ownerID: UUID) -> Bool {
        AttachmentLimits.canAdd(kind, to: owner)
    }

    /// Records an attachment whose file is already in place. Nil when the
    /// owner can't hold that kind.
    @discardableResult
    func addAttachment(
        id: UUID = UUID(),
        kind: AttachmentKind,
        to owner: AttachmentOwner,
        ownerID: UUID,
        byteSize: Int,
        duration: Double? = nil,
        pageCount: Int? = nil,
        caption: String = ""
    ) -> Attachment? {
        let existing = attachments(for: owner, id: ownerID)
        guard AttachmentLimits.canAdd(kind, to: owner) else { return nil }
        let attachment = Attachment(id: id, owner: owner, ownerID: ownerID, kind: kind)
        attachment.byteSize = byteSize
        attachment.duration = duration
        attachment.pageCount = pageCount
        attachment.caption = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        attachment.sortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        context.insert(attachment)
        save()
        return attachment
    }

    func setCaption(_ caption: String, on attachment: Attachment) {
        let trimmed = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard trimmed != attachment.caption else { return }
        attachment.caption = trimmed
        attachment.updatedAt = .now
        save()
    }

    /// A Pencil page changed: its new size, and the file goes up again.
    func attachmentFileChanged(_ attachment: Attachment, byteSize: Int) {
        attachment.byteSize = byteSize
        attachment.needsUpload = true
        attachment.updatedAt = .now
        save()
    }

    /// Moves an attachment one place earlier or later among its owner's.
    func move(_ attachment: Attachment, by offset: Int) {
        var ordered = attachments(for: attachment.owner, id: attachment.ownerID)
        guard let index = ordered.firstIndex(where: { $0.id == attachment.id }) else { return }
        let target = min(max(0, index + offset), ordered.count - 1)
        guard target != index else { return }
        ordered.remove(at: index)
        ordered.insert(attachment, at: target)
        let now = Date.now
        for (position, item) in ordered.enumerated() where item.sortOrder != position {
            item.sortOrder = position
            item.updatedAt = now
        }
        save()
    }

    func delete(_ attachment: Attachment) {
        discardAttachment(attachment)
        save()
    }

    /// Soft-deletes every attachment of a prayer or sermon being deleted.
    /// Doesn't save.
    func deleteAttachments(of owner: AttachmentOwner, id ownerID: UUID) {
        for attachment in attachments(for: owner, id: ownerID) {
            discardAttachment(attachment)
        }
    }

    private func discardAttachment(_ attachment: Attachment) {
        recordDeletion(of: attachment.id, in: SyncTable.attachments)
        AttachmentTransfers.app?.discard(fileName: attachment.fileName)
        context.delete(attachment)
    }
}
