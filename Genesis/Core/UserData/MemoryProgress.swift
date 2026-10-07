import Foundation

/// Gentle levels for Memorise, by passages memorised (mastery `.memorised`,
/// that is, remembered over three weeks apart). Computed from the synced
/// verses, so nothing extra is stored.
enum MemoryLevel: Int, CaseIterable, Comparable, Sendable {
    case seed, sprout, sapling, tree, cedar

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Passages memorised to reach the level.
    var threshold: Int {
        switch self {
        case .seed: 0
        case .sprout: 1
        case .sapling: 5
        case .tree: 12
        case .cedar: 25
        }
    }

    var title: String {
        switch self {
        case .seed: String(localized: "Seed", comment: "Memorize level")
        case .sprout: String(localized: "Sprout", comment: "Memorize level")
        case .sapling: String(localized: "Sapling", comment: "Memorize level")
        case .tree: String(localized: "Tree", comment: "Memorize level")
        case .cedar: String(localized: "Cedar", comment: "Memorize level: the highest")
        }
    }

    var symbol: String {
        switch self {
        case .seed: "circle.circle"
        case .sprout: "leaf"
        case .sapling: "camera.macro"
        case .tree: "tree"
        case .cedar: "tree.fill"
        }
    }

    var next: MemoryLevel? { MemoryLevel(rawValue: rawValue + 1) }

    static func level(memorised count: Int) -> MemoryLevel {
        allCases.last { count >= $0.threshold } ?? .seed
    }

    /// 0...1 from this level's threshold to the next (1 at the top level).
    static func progress(memorised count: Int) -> Double {
        let level = level(memorised: count)
        guard let next = level.next else { return 1 }
        let span = Double(next.threshold - level.threshold)
        return min(1, max(0, Double(count - level.threshold) / span))
    }
}

/// Days in a row with some Memorise practice (a review or a game). Kept on
/// this device only, in UserDefaults through `@AppStorage(storageKey)`.
struct PracticeStreak: Equatable, Sendable {
    static let storageKey = "memorise.practiceStreak"

    /// Days in a row up to `lastDay`.
    var count: Int = 0
    var longest: Int = 0
    /// Start of the last day with practice.
    var lastDay: Date?

    /// The streak as it stands on `date`: it lasts through the day after the
    /// last practice, then starts again from zero.
    func current(on date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let lastDay, let gap = Self.days(from: lastDay, to: date, calendar: calendar) else { return 0 }
        return gap <= 1 ? count : 0
    }

    func hasPractised(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastDay else { return false }
        return Self.days(from: lastDay, to: date, calendar: calendar) == 0
    }

    /// The streak after practising on `date`: unchanged later the same day,
    /// one longer the next day, back to 1 after a missed day.
    func recording(on date: Date = .now, calendar: Calendar = .current) -> PracticeStreak {
        var next = self
        let gap = lastDay.flatMap { Self.days(from: $0, to: date, calendar: calendar) }
        switch gap {
        case let days? where days <= 0: return self   // same day (or the clock went back)
        case 1?: next.count = count + 1
        default: next.count = 1
        }
        next.lastDay = calendar.startOfDay(for: date)
        next.longest = max(longest, next.count)
        return next
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day
    }
}

/// Stored as "count|longest|lastDay" so `@AppStorage` can keep it.
extension PracticeStreak: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, let count = Int(parts[0]), let longest = Int(parts[1]) else { return nil }
        self.count = count
        self.longest = longest
        lastDay = Double(parts[2]).map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    var rawValue: String {
        "\(count)|\(longest)|\(lastDay.map { String($0.timeIntervalSinceReferenceDate) } ?? "")"
    }
}
