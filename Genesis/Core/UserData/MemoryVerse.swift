import Foundation
import SwiftData

/// A passage being learned by heart (Premium). Only the reference and the
/// review schedule are stored; the words always come from the Bible database
/// in the chosen translation.
@Model
final class MemoryVerse {
    @Attribute(.unique) var id: UUID
    /// First and last verse (one chapter).
    var startRaw: Int
    var endRaw: Int
    /// The translation being memorised, e.g. "KJV".
    var translationID: String
    var ease: Double = MemorySchedule.startingEase
    var intervalDays: Double = 0
    var repetitions: Int = 0
    var dueAt: Date
    var lastReviewedAt: Date? = nil
    var reviewCount: Int = 0
    var createdAt: Date
    var updatedAt: Date

    init(start: VerseID, end: VerseID, translationID: String, now: Date = .now) {
        id = UUID()
        startRaw = start.rawValue
        endRaw = max(end.rawValue, start.rawValue)
        self.translationID = translationID
        dueAt = now
        createdAt = now
        updatedAt = now
    }

    var start: VerseID { VerseID(rawValue: startRaw) }
    var end: VerseID { VerseID(rawValue: endRaw) }

    var reference: PassageReference {
        PassageReference(verses: [start, end]) ?? PassageReference(verse: start)
    }

    var schedule: MemorySchedule {
        get { MemorySchedule(ease: ease, intervalDays: intervalDays, repetitions: repetitions, dueAt: dueAt) }
        set {
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            dueAt = newValue.dueAt
        }
    }

    func isDue(on date: Date = .now) -> Bool { dueAt <= date }

    var mastery: MemoryMastery { schedule.mastery }
}

/// How well a review went.
enum MemoryGrade: String, CaseIterable, Identifiable, Sendable {
    case again, hard, good, easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: String(localized: "Again", comment: "Memorise: I didn't remember it")
        case .hard: String(localized: "Hard", comment: "Memorise: I remembered with difficulty")
        case .good: String(localized: "Good", comment: "Memorise: I remembered it")
        case .easy: String(localized: "Easy", comment: "Memorise: I knew it easily")
        }
    }
}

enum MemoryMastery: Int, Comparable, Sendable {
    case new, learning, familiar, memorised

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .new: String(localized: "New", comment: "Memorise: not reviewed yet")
        case .learning: String(localized: "Learning", comment: "Memorise progress")
        case .familiar: String(localized: "Familiar", comment: "Memorise progress")
        case .memorised: String(localized: "Memorised", comment: "Memorise progress")
        }
    }

    /// 0...1 for a progress ring.
    var fraction: Double { Double(rawValue) / 3 }
}

/// Spaced repetition (a gentle SM-2): each good review pushes the next one
/// further out; forgetting brings it back the same day.
struct MemorySchedule: Equatable, Sendable {
    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var dueAt: Date

    static let startingEase = 2.5
    static let minimumEase = 1.3

    func reviewed(_ grade: MemoryGrade, at now: Date, calendar: Calendar = .current) -> MemorySchedule {
        var next = self
        switch grade {
        case .again:
            next.repetitions = 0
            next.intervalDays = 0
            next.ease = max(Self.minimumEase, ease - 0.2)
            next.dueAt = now.addingTimeInterval(10 * 60)
            return next
        case .hard:
            next.intervalDays = max(1, intervalDays * 1.2)
            next.ease = max(Self.minimumEase, ease - 0.15)
        case .good:
            next.intervalDays = switch repetitions {
            case 0: 1
            case 1: 3
            default: max(intervalDays + 1, (intervalDays * ease).rounded())
            }
        case .easy:
            next.intervalDays = repetitions == 0 ? 4 : max(intervalDays + 2, (intervalDays * ease * 1.3).rounded())
            next.ease = ease + 0.15
        }
        next.repetitions = repetitions + 1
        // Due at the start of that day, so a verse reviewed in the evening is
        // ready again in the morning.
        let day = calendar.startOfDay(for: now)
        next.dueAt = calendar.date(byAdding: .day, value: Int(next.intervalDays.rounded()), to: day) ?? now
        return next
    }

    var mastery: MemoryMastery {
        if repetitions == 0 { return .new }
        if intervalDays < 7 { return .learning }
        if intervalDays < 21 { return .familiar }
        return .memorised
    }
}

/// A hint for recalling a passage: its opening words, verbatim, followed by
/// an ellipsis ("For God so loved the world…"). Each step reveals a few more.
enum MemoryHint {
    static let wordsPerStep = 4

    /// The first `words` words of the passage (all of it if that's shorter).
    static func opening(_ text: String, words: Int) -> String {
        let all = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words < all.count else { return text }
        return all.prefix(max(words, 1)).joined(separator: " ") + "\u{2026}"
    }

    /// True once `words` shows the whole passage.
    static func isComplete(_ text: String, words: Int) -> Bool {
        words >= text.split(separator: " ", omittingEmptySubsequences: true).count
    }
}
