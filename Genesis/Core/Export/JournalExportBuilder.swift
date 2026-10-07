import Foundation
import PencilKit
import SwiftData
import UIKit

/// Gathers a sermon, a prayer or a stretch of the prayer journal into a
/// `JournalExport`: verse text verbatim from the Bible being read, with its
/// abbreviation; photos and Pencil pages from this device's attachment files.
@MainActor
struct JournalExportBuilder {
    let library: BibleLibrary
    let store: StudyStore
    let files: AttachmentFiles
    /// The reader's typeface, already resolved for Premium.
    let font: ReaderFont

    func export(_ sermon: Sermon) -> JournalExport {
        JournalExport(title: sermon.displayTitle, subtitle: sermonSubtitle(sermon), entries: [entry(for: sermon)], font: font)
    }

    func export(_ prayer: Prayer) -> JournalExport {
        JournalExport(title: prayer.displayTitle, subtitle: String(localized: "From my prayer journal"), entries: [entry(for: prayer)], font: font)
    }

    /// The prayer journal between two days, optionally one category.
    func exportJournal(_ prayers: [Prayer], filter: PrayerExportFilter) -> JournalExport {
        let byID = Dictionary(prayers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = filter.apply(prayers.map(\.facts)).compactMap { byID[$0.id] }
        let range = "\(filter.from.formatted(date: .abbreviated, time: .omitted)) \u{2013} \(filter.through.formatted(date: .abbreviated, time: .omitted))"
        let subtitle = filter.category.map { "\($0.title) · \(range)" } ?? range
        return JournalExport(title: String(localized: "Prayer Journal"), subtitle: subtitle, entries: chosen.map { entry(for: $0) }, font: font)
    }

    // MARK: Entries

    private func entry(for sermon: Sermon) -> JournalExport.Entry {
        var entry = JournalExport.Entry(title: sermon.displayTitle)
        entry.details = [
            sermon.preachedAt.formatted(date: .complete, time: .omitted),
            [sermon.preacher, sermon.church].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · "),
            sermon.series ?? "",
        ]
        entry.body = sermon.body
        entry.passages = passages(sermon.passages)
        addAttachments(of: .sermon, id: sermon.id, to: &entry)
        return entry
    }

    private func entry(for prayer: Prayer) -> JournalExport.Entry {
        var entry = JournalExport.Entry(title: prayer.displayTitle)
        entry.details = [prayer.createdAt.formatted(date: .complete, time: .omitted), prayer.category.title]
        entry.body = prayer.body
        if prayer.isAnswered {
            let note = prayer.answerNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let when = prayer.answeredAt.map { $0.formatted(date: .long, time: .omitted) } ?? ""
            entry.answer = [when, note].filter { !$0.isEmpty }.joined(separator: " \u{2014} ")
        }
        entry.passages = passages(prayer.passages)
        addAttachments(of: .prayer, id: prayer.id, to: &entry)
        return entry
    }

    private func sermonSubtitle(_ sermon: Sermon) -> String {
        let church = sermon.church.trimmingCharacters(in: .whitespaces)
        let date = sermon.preachedAt.formatted(date: .long, time: .omitted)
        return church.isEmpty ? date : "\(church) · \(date)"
    }

    /// Each passage verbatim from the current Bible; one missing from it is left out.
    private func passages(_ passages: [PrayerPassage]) -> [JournalExport.Passage] {
        let translation = library.currentTranslation
        return passages.compactMap { passage in
            let verses = (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
            guard !verses.isEmpty else { return nil }
            return JournalExport.Passage(
                reference: passage.reference.description(in: translation.language),
                translation: translation.abbreviation,
                text: verses.map(\.plainText).joined(separator: " ")
            )
        }
    }

    private func addAttachments(of owner: AttachmentOwner, id: UUID, to entry: inout JournalExport.Entry) {
        for attachment in store.attachments(for: owner, id: id) {
            switch attachment.kind {
            case .photo:
                if let data = try? files.read(attachment.fileName) {
                    entry.pictures.append(JournalExport.Picture(data: data, caption: attachment.caption))
                }
            case .drawing:
                if let data = try? files.read(attachment.fileName), let image = Self.drawingImage(data) {
                    entry.pictures.append(JournalExport.Picture(data: image, caption: attachment.caption))
                }
            case .audio:
                entry.recordings.append(JournalExport.Recording(duration: attachment.duration ?? 0, caption: attachment.caption))
            case .pdf:
                entry.documents.append(JournalExport.Document(pageCount: attachment.pageCount ?? 0, caption: attachment.caption))
            }
        }
    }

    /// A Pencil page as a PNG with dark ink on a white page.
    static func drawingImage(_ data: Data) -> Data? {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)
        var png: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let image = drawing.image(from: bounds, scale: 2)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            png = renderer.pngData { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))
                image.draw(in: CGRect(origin: .zero, size: bounds.size))
            }
        }
        return png
    }
}
