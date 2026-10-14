import Foundation
import SwiftData

extension Milestones.Stats {
    /// Today's numbers: reading from `ReadingProgress`, answered prayers and
    /// passages by heart from the person's data (only for features they
    /// show, so a hidden feature never pops up a celebration).
    @MainActor
    static func current(progress: ReadingProgress, context: ModelContext, features: FeaturePreferences, now: Date = .now) -> Milestones.Stats {
        var stats = Milestones.Stats()
        stats.longestStreak = max(progress.longestStreak, progress.streak(on: now))
        stats.chapters = progress.chaptersRead.count
        stats.books = progress.booksCompleted
        if features.isOn(.prayer) {
            stats.answeredPrayers = (try? context.fetchCount(FetchDescriptor<Prayer>(predicate: #Predicate<Prayer> { $0.isAnswered }))) ?? 0
        }
        if features.isOn(.memorise) {
            let verses = (try? context.fetch(FetchDescriptor<MemoryVerse>())) ?? []
            stats.memorised = verses.filter { $0.mastery == .memorised }.count
        }
        return stats
    }
}
