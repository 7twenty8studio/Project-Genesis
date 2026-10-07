import Foundation

/// Everything a journal PDF shows, gathered beforehand (verse text from the
/// Bible database, verbatim; photos and Pencil pages as image data), so the
/// renderer needs no app state and can run off the main thread.
struct JournalExport: Sendable {
    struct Passage: Sendable, Hashable {
        /// "John 3:16", in the Bible's language.
        let reference: String
        /// The translation's abbreviation, e.g. "KJV".
        let translation: String
        /// Verbatim from the Bible database; never edited.
        let text: String
    }

    struct Picture: Sendable {
        /// JPEG or PNG data.
        let data: Data
        let caption: String
    }

    struct Recording: Sendable, Hashable {
        let duration: TimeInterval
        let caption: String
    }

    struct Document: Sendable, Hashable {
        let pageCount: Int
        let caption: String
    }

    struct Entry: Sendable {
        var title: String
        /// Lines under the title: date, church and preacher, category.
        var details: [String] = []
        /// Sermon notes are Markdown (`SermonMarkdown`); prayers plain text.
        var body: String = ""
        /// How an answered prayer was answered.
        var answer: String? = nil
        var passages: [Passage] = []
        var pictures: [Picture] = []
        var recordings: [Recording] = []
        var documents: [Document] = []
    }

    var title: String
    var subtitle: String
    var entries: [Entry]
    /// The reader's typeface (a Premium face only with Premium).
    var font: ReaderFont = .newYork
    var createdAt: Date = .now
}

/// Which prayers go into a journal export.
struct PrayerExportFilter: Sendable, Equatable {
    var from: Date
    var through: Date
    /// Nil for every category.
    var category: PrayerCategory?

    /// Prayers asked between the two days (inclusive, whole days), oldest first.
    func apply(_ prayers: [PrayerFacts], calendar: Calendar = .current) -> [PrayerFacts] {
        let start = calendar.startOfDay(for: min(from, through))
        let endDay = calendar.startOfDay(for: max(from, through))
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return prayers
            .filter { $0.hasContent && $0.createdAt >= start && $0.createdAt < end && (category == nil || $0.category == category) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
