import Foundation
import SwiftData

/// Notes from a sermon: who preached, where, when, the passages (verse ids
/// only, never the text) and the notes themselves as Markdown text
/// (`SermonMarkdown`). Free for everyone, with no limits.
///
/// Premium extras (photos, a recording, Pencil pages, PDF import and export)
/// will hang off a sermon as separate attachment records keyed by `id`, so
/// this model and the sermons table don't need to change for them.
@Model
final class Sermon {
    @Attribute(.unique) var id: UUID
    var title: String = ""
    var preacher: String = ""
    /// Free text; the editor suggests the person's earlier churches.
    var church: String = ""
    /// When it was preached (defaults to when the note was started).
    var preachedAt: Date = Date.now
    var series: String? = nil
    /// The notes as Markdown: **bold**, *italic*, "## " headings, "- " and
    /// "1. " lists and "> " quotes.
    var body: String = ""
    /// Passages as "start-end" verse ids separated by commas (`PrayerPassage`).
    /// Ids only, never the text.
    var passagesRaw: String = ""
    var isFavourite: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(church: String = "", preachedAt: Date = .now) {
        id = UUID()
        self.church = church
        self.preachedAt = preachedAt
        createdAt = .now
        updatedAt = .now
    }

    /// The most passages one sermon keeps.
    static let maximumPassages = 30

    var passages: [PrayerPassage] {
        get { PrayerPassage.decode(passagesRaw) }
        set { passagesRaw = PrayerPassage.encode(newValue) }
    }

    var hasContent: Bool {
        [title, preacher, body].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !passagesRaw.isEmpty
    }

    var facts: SermonFacts {
        SermonFacts(
            id: id,
            title: title,
            preacher: preacher,
            church: church,
            series: series ?? "",
            body: body,
            preachedAt: preachedAt,
            isFavourite: isFavourite,
            hasContent: hasContent
        )
    }

    var displayTitle: String { facts.displayTitle }
}
