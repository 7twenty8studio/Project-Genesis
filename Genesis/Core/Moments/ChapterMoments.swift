import Foundation
import Observation

/// "Once per chapter per day": the pure rule behind chapter-complete moments.
enum ChapterMomentRule {
    /// "2026-10-06|chapter:43003" or "2026-10-06|plan:<id>:12".
    static func key(for subject: String, on date: Date, calendar: Calendar) -> String {
        "\(Timestamp.dayString(from: date, calendar: calendar))|\(subject)"
    }

    static func chapterSubject(_ chapter: ChapterID) -> String {
        "chapter:\(chapter.book * 1_000 + chapter.chapter)"
    }

    static func planDaySubject(planID: String, day: Int) -> String {
        "plan:\(planID):\(day)"
    }

    static func shouldCelebrate(key: String, alreadyCelebrated: Set<String>) -> Bool {
        !alreadyCelebrated.contains(key)
    }

    /// Only today's keys are worth keeping.
    static func pruned(_ keys: Set<String>, on date: Date, calendar: Calendar) -> Set<String> {
        let prefix = Timestamp.dayString(from: date, calendar: calendar) + "|"
        return keys.filter { $0.hasPrefix(prefix) }
    }
}

/// A brief gold-ribbon moment when a chapter or a plan day is finished
/// (part of the deluxe look, `.premiumThemes`; the overlay checks access).
/// At most once per chapter (or plan day) per day; never in UI tests
/// unless launched with `-uiTestingMoments`.
@MainActor
@Observable
final class ChapterMoments {
    enum Place: Sendable {
        case reader, plans, home
    }

    enum Kind: Equatable, Sendable {
        case chapter(ChapterID)
        case planDay(Int)
    }

    struct Moment: Identifiable, Equatable, Sendable {
        let id = UUID()
        let kind: Kind
        let place: Place
        let createdAt: Date

        /// A moment nobody saw (its screen wasn't showing) isn't shown later.
        func isFresh(at date: Date = .now) -> Bool {
            date.timeIntervalSince(createdAt) < 3
        }
    }

    static let shared = ChapterMoments()

    /// The moment showing now, if any.
    private(set) var current: Moment?

    @ObservationIgnored let isEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    private static let celebratedKey = "moments.celebrated"

    init(
        isEnabled: Bool = ChapterMoments.enabledByLaunchArguments(ProcessInfo.processInfo.arguments),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.isEnabled = isEnabled
        self.defaults = defaults
        self.calendar = calendar
    }

    nonisolated static func enabledByLaunchArguments(_ arguments: [String]) -> Bool {
        !arguments.contains("-uiTesting") || arguments.contains("-uiTestingMoments")
    }

    /// The person reached the end of a chapter. True when a moment shows.
    @discardableResult
    func chapterFinished(_ chapter: ChapterID, in place: Place = .reader, now: Date = .now) -> Bool {
        celebrate(.chapter(chapter), subject: ChapterMomentRule.chapterSubject(chapter), in: place, now: now)
    }

    /// A reading-plan day was marked as read. True when a moment shows.
    @discardableResult
    func planDayCompleted(_ day: Int, planID: String, in place: Place, now: Date = .now) -> Bool {
        celebrate(.planDay(day), subject: ChapterMomentRule.planDaySubject(planID: planID, day: day), in: place, now: now)
    }

    func dismiss(_ moment: Moment) {
        if current?.id == moment.id { current = nil }
    }

    private func celebrate(_ kind: Kind, subject: String, in place: Place, now: Date) -> Bool {
        guard isEnabled else { return false }
        let key = ChapterMomentRule.key(for: subject, on: now, calendar: calendar)
        var celebrated = ChapterMomentRule.pruned(Set(defaults.stringArray(forKey: Self.celebratedKey) ?? []), on: now, calendar: calendar)
        guard ChapterMomentRule.shouldCelebrate(key: key, alreadyCelebrated: celebrated) else { return false }
        celebrated.insert(key)
        defaults.set(Array(celebrated), forKey: Self.celebratedKey)
        current = Moment(kind: kind, place: place, createdAt: now)
        return true
    }
}
