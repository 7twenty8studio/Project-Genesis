import Foundation
import Observation

/// A daily reading goal: chapters or minutes.
enum ReadingGoal: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case oneChapter
    case threeChapters
    case fiveMinutes
    case tenMinutes
    case twentyMinutes

    var id: String { rawValue }

    enum Unit: Sendable { case chapters, minutes }

    var unit: Unit {
        switch self {
        case .none, .oneChapter, .threeChapters: .chapters
        case .fiveMinutes, .tenMinutes, .twentyMinutes: .minutes
        }
    }

    /// How many chapters or minutes a day; 0 for no goal.
    var target: Int {
        switch self {
        case .none: 0
        case .oneChapter: 1
        case .threeChapters: 3
        case .fiveMinutes: 5
        case .tenMinutes: 10
        case .twentyMinutes: 20
        }
    }

    var title: String {
        switch self {
        case .none: String(localized: "No daily goal")
        case .oneChapter: String(localized: "1 chapter a day")
        case .threeChapters: String(localized: "3 chapters a day")
        case .fiveMinutes: String(localized: "5 minutes a day")
        case .tenMinutes: String(localized: "10 minutes a day")
        case .twentyMinutes: String(localized: "20 minutes a day")
        }
    }

    /// Today's progress, from chapters opened and seconds in the reader.
    func progress(chaptersToday: Int, secondsToday: Int) -> GoalProgress? {
        guard self != ReadingGoal.none else { return nil }
        let done = unit == .chapters ? chaptersToday : secondsToday / 60
        return GoalProgress(goal: self, done: min(done, target), target: target)
    }
}

struct GoalProgress: Sendable, Equatable {
    let goal: ReadingGoal
    let done: Int
    let target: Int

    var isMet: Bool { done >= target }
    var fraction: Double { target > 0 ? Double(done) / Double(target) : 0 }
    var remaining: Int { max(target - done, 0) }

    /// "1 of 3 chapters", "4 of 10 minutes".
    var label: String {
        switch goal.unit {
        case .chapters: String(localized: "\(done) of \(target) chapters", comment: "Daily goal progress")
        case .minutes: String(localized: "\(done) of \(target) minutes", comment: "Daily goal progress")
        }
    }

    /// "1 more chapter to reach today's goal."
    var nudge: String {
        switch goal.unit {
        case .chapters:
            remaining == 1
                ? String(localized: "1 more chapter to reach today's goal.")
                : String(localized: "\(remaining) more chapters to reach today's goal.")
        case .minutes:
            String(localized: "\(remaining) more minutes to reach today's goal.")
        }
    }
}

/// The person's goal and streak settings (Settings › Goals & Streaks).
@MainActor
@Observable
final class GoalPreferences {
    var goal: ReadingGoal {
        didSet { defaults.set(goal.rawValue, forKey: Keys.goal) }
    }

    /// Streak shields: one missed day a week doesn't break the streak.
    var usesStreakShields: Bool {
        didSet { defaults.set(usesStreakShields, forKey: Keys.shields) }
    }

    /// Milestones already celebrated (shown once each).
    private(set) var celebrated: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let goal = "goals.daily"
        static let shields = "goals.streakShields"
        static let celebrated = "goals.celebratedMilestones"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        goal = defaults.string(forKey: Keys.goal).flatMap(ReadingGoal.init(rawValue:)) ?? ReadingGoal.none
        usesStreakShields = defaults.object(forKey: Keys.shields) as? Bool ?? true
        celebrated = Set(defaults.stringArray(forKey: Keys.celebrated) ?? [])
    }

    /// True before anything was ever celebrated (an existing reader seeing
    /// milestones for the first time gets theirs quietly, not a parade).
    var hasCelebratedAny: Bool { defaults.object(forKey: Keys.celebrated) != nil }

    func markCelebrated(_ ids: some Sequence<String>) {
        celebrated.formUnion(ids)
        defaults.set(Array(celebrated).sorted(), forKey: Keys.celebrated)
    }
}

extension ReadingStreak {
    /// The streak with shields: walking back from today (or yesterday, as
    /// today isn't missed yet), a single missed day between two reading days
    /// is covered by a shield, at most once in any seven days. Covered days
    /// keep the streak alive but don't add to it. `lastShield` is the most
    /// recent covered day.
    static func walk(_ days: Set<String>, endingOn date: Date, calendar: Calendar, shields: Bool) -> (length: Int, lastShield: Date?) {
        var day = calendar.startOfDay(for: date)
        if !days.contains(Timestamp.dayString(from: day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return (0, nil) }
            day = yesterday
        }
        var count = 0
        // Covered days, newest first (the walk goes back in time).
        var covered: [Date] = []
        while true {
            if days.contains(Timestamp.dayString(from: day, calendar: calendar)) {
                count += 1
            } else {
                guard shields,
                      let before = calendar.date(byAdding: .day, value: -1, to: day),
                      days.contains(Timestamp.dayString(from: before, calendar: calendar)) else { break }
                if let newer = covered.last,
                   (calendar.dateComponents([.day], from: day, to: newer).day ?? 0) < 7 { break }
                covered.append(day)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return (count, covered.first)
    }

    /// Whether a shield is ready: none used in the last seven days.
    static func shieldReady(lastShield: Date?, on date: Date, calendar: Calendar) -> Bool {
        guard let lastShield else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastShield), to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 7
    }
}
