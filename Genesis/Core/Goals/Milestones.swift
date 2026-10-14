import Foundation

/// Something worth celebrating: a streak, chapters, books, answered prayers
/// or passages learned by heart. Each is celebrated once (`GoalPreferences`).
struct Milestone: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case streak, chapters, books, prayers, memorised }

    let kind: Kind
    let count: Int

    var id: String { "\(kind.rawValue).\(count)" }

    var title: String {
        switch kind {
        case .streak: String(localized: "\(count) days in a row", comment: "Milestone")
        case .chapters:
            count == Milestones.wholeBibleChapters
                ? String(localized: "Every chapter of the Bible", comment: "Milestone")
                : String(localized: "\(count) chapters read", comment: "Milestone")
        case .books:
            count == 1
                ? String(localized: "Your first book of the Bible", comment: "Milestone")
                : count == 66
                    ? String(localized: "All 66 books", comment: "Milestone")
                    : String(localized: "\(count) books finished", comment: "Milestone")
        case .prayers:
            count == 1
                ? String(localized: "Your first answered prayer", comment: "Milestone")
                : String(localized: "\(count) answered prayers", comment: "Milestone")
        case .memorised:
            count == 1
                ? String(localized: "Your first passage by heart", comment: "Milestone")
                : String(localized: "\(count) passages by heart", comment: "Milestone")
        }
    }

    var detail: String {
        switch kind {
        case .streak: String(localized: "Day after day in the Word. Keep going!")
        case .chapters: String(localized: "Every chapter is a step further into the story.")
        case .books: String(localized: "Start to finish, every chapter read.")
        case .prayers: String(localized: "Remember what God has done.")
        case .memorised: String(localized: "Hidden in your heart, ready when you need it.")
        }
    }

    var systemImage: String {
        switch kind {
        case .streak: "flame.fill"
        case .chapters: "book.pages.fill"
        case .books: "books.vertical.fill"
        case .prayers: "hands.and.sparkles.fill"
        case .memorised: "brain.head.profile"
        }
    }
}

enum Milestones {
    static let wholeBibleChapters = 1_189

    struct Stats: Sendable, Equatable {
        var longestStreak = 0
        var chapters = 0
        var books = 0
        var answeredPrayers = 0
        var memorised = 0
    }

    static let steps: [(Milestone.Kind, [Int])] = [
        (.streak, [3, 7, 30, 100, 365]),
        (.chapters, [10, 50, 100, 250, 500, 1_000, wholeBibleChapters]),
        (.books, [1, 5, 10, 25, 66]),
        (.prayers, [1, 10, 50]),
        (.memorised, [1, 10, 25]),
    ]

    /// Every milestone reached, in the order above.
    static func earned(_ stats: Stats) -> [Milestone] {
        steps.flatMap { kind, counts in
            let value: Int
            switch kind {
            case .streak: value = stats.longestStreak
            case .chapters: value = stats.chapters
            case .books: value = stats.books
            case .prayers: value = stats.answeredPrayers
            case .memorised: value = stats.memorised
            }
            return counts.filter { value >= $0 }.map { Milestone(kind: kind, count: $0) }
        }
    }

    /// The next milestone of each kind, for "what's next".
    static func next(_ stats: Stats) -> [Milestone] {
        let earnedIDs = Set(earned(stats).map(\.id))
        return steps.compactMap { kind, counts in
            counts.map { Milestone(kind: kind, count: $0) }.first { !earnedIDs.contains($0.id) }
        }
    }

    /// Reached but not yet celebrated, the biggest first. Someone who already
    /// read a lot before milestones existed isn't shown a parade: on the first
    /// look everything reached so far is taken as celebrated.
    static func toCelebrate(_ stats: Stats, celebrated: Set<String>, hasCelebratedAny: Bool) -> (show: Milestone?, markQuietly: [String]) {
        let fresh = earned(stats).filter { !celebrated.contains($0.id) }
        guard hasCelebratedAny else { return (nil, fresh.map(\.id)) }
        // One at a time: the newest-feeling (largest of its kind, last kind wins ties).
        return (fresh.last, [])
    }
}
