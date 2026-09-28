import Foundation
import Observation

/// Remembers where the person is reading so the app reopens in place.
/// Stored in UserDefaults for an instant read at launch.
@MainActor
@Observable
final class ReadingProgress {
    /// The first verse visible when the reader was last used.
    private(set) var position: VerseID
    private(set) var lastReadAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    private static let positionKey = "progress.position"
    private static let dateKey = "progress.lastReadAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.integer(forKey: Self.positionKey)
        position = raw > 0 ? VerseID(rawValue: raw) : ChapterID.genesis1.firstVerse
        lastReadAt = defaults.object(forKey: Self.dateKey) as? Date
    }

    var hasStartedReading: Bool { lastReadAt != nil }

    func update(_ verse: VerseID) {
        guard verse != position || lastReadAt == nil else { return }
        position = verse
        lastReadAt = .now
        defaults.set(verse.rawValue, forKey: Self.positionKey)
        defaults.set(lastReadAt, forKey: Self.dateKey)
    }

    /// Fraction of the current book's chapters before this one, 0...1.
    var progressThroughBook: Double {
        let book = position.chapterID.bibleBook
        return Double(position.chapter - 1) / Double(max(book.chapterCount, 1))
    }
}
