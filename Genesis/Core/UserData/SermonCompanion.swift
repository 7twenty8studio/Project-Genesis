import Foundation

// The Sermon Companion's pure logic: search, favourites, grouping by date or
// church, church suggestions, verse lookup and Church Mode's screen rule.
// Free for everyone, with no limits.

/// What the sermon list needs from a sermon, without SwiftData.
struct SermonFacts: Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var preacher: String
    var church: String
    var series: String
    /// The notes as Markdown.
    var body: String
    var preachedAt: Date
    var isFavourite: Bool
    /// False for a sermon opened and left empty (it's discarded on close).
    var hasContent: Bool = true

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = SermonMarkdown.plainText(body)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return firstLine.isEmpty ? String(localized: "Sermon Notes") : firstLine
    }

    /// The church as typed, without stray spaces.
    var churchName: String { church.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Search across the title, preacher, church, series and notes.
enum SermonSearch {
    static func matches(_ sermon: SermonFacts, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let fields = [sermon.title, sermon.preacher, sermon.church, sermon.series, SermonMarkdown.plainText(sermon.body)]
        return fields.contains { $0.localizedStandardContains(trimmed) }
    }
}

/// The list's sections: by date (this week, then by month) or by church.
enum SermonGrouping {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case date, church
        var id: String { rawValue }
    }

    struct Section: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            /// This week (and anything dated later).
            case thisWeek
            /// The first moment of the month.
            case month(Date)
            /// A church's name, as most recently typed.
            case church(String)
            /// Sermons with no church written down.
            case noChurch
        }

        let kind: Kind
        /// Newest first.
        let sermons: [SermonFacts]

        var id: Kind { kind }
    }

    /// Sermons with content that match the search and the favourites filter,
    /// newest first.
    static func visible(_ sermons: [SermonFacts], query: String, favouritesOnly: Bool) -> [SermonFacts] {
        sermons
            .filter { $0.hasContent && (!favouritesOnly || $0.isFavourite) && SermonSearch.matches($0, query: query) }
            .sorted(by: newestFirst)
    }

    static func sections(_ sermons: [SermonFacts], mode: Mode, now: Date = .now, calendar: Calendar = .current) -> [Section] {
        switch mode {
        case .date: byDate(sermons, now: now, calendar: calendar)
        case .church: byChurch(sermons)
        }
    }

    /// "This Week" first, then each earlier month, newest first.
    static func byDate(_ sermons: [SermonFacts], now: Date = .now, calendar: Calendar = .current) -> [Section] {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: sermons) { sermon -> Section.Kind in
            if sermon.preachedAt >= weekStart { return .thisWeek }
            let month = calendar.dateInterval(of: .month, for: sermon.preachedAt)?.start ?? calendar.startOfDay(for: sermon.preachedAt)
            return .month(month)
        }
        return grouped
            .map { Section(kind: $0.key, sermons: $0.value.sorted(by: newestFirst)) }
            .sorted { lhs, rhs in
                switch (lhs.kind, rhs.kind) {
                case (.thisWeek, _): true
                case (_, .thisWeek): false
                case let (.month(left), .month(right)): left > right
                default: false
                }
            }
    }

    /// One section per church (spelling and case don't matter), A to Z, with
    /// sermons that have no church last.
    static func byChurch(_ sermons: [SermonFacts]) -> [Section] {
        let grouped = Dictionary(grouping: sermons) { churchKey($0.church) }
        let sections = grouped.map { key, members -> Section in
            let sorted = members.sorted(by: newestFirst)
            let name = sorted.first?.churchName ?? ""
            return Section(kind: key.isEmpty ? .noChurch : .church(name), sermons: sorted)
        }
        return sections.sorted { lhs, rhs in
            switch (lhs.kind, rhs.kind) {
            case (.noChurch, _): false
            case (_, .noChurch): true
            case let (.church(left), .church(right)): left.localizedStandardCompare(right) == .orderedAscending
            default: false
            }
        }
    }

    /// Churches the person has written before, most recent first, matching
    /// what's typed so far (and not just repeating it).
    static func churchSuggestions(_ sermons: [SermonFacts], typed: String, limit: Int = 4) -> [String] {
        let typedKey = churchKey(typed)
        var seen = Set<String>()
        var result: [String] = []
        for sermon in sermons.sorted(by: newestFirst) {
            let key = churchKey(sermon.church)
            guard !key.isEmpty, key != typedKey, seen.insert(key).inserted else { continue }
            if typedKey.isEmpty || key.contains(typedKey) {
                result.append(sermon.churchName)
            }
            if result.count == limit { break }
        }
        return result
    }

    /// How two spellings of one church are matched: case, accents and
    /// spacing don't matter.
    static func churchKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func newestFirst(_ lhs: SermonFacts, _ rhs: SermonFacts) -> Bool {
        lhs.preachedAt == rhs.preachedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.preachedAt > rhs.preachedAt
    }
}

/// "John 3:16" or "Juan 3:16" typed in the editor: the passage, if the Bible
/// being read has it. Uses the reader's reference parser (English and
/// Spanish book names).
enum SermonLookup {
    enum Outcome: Equatable, Sendable {
        case found(PrayerPassage)
        /// Nothing typed yet.
        case empty
        case notAReference
        case notInBible
    }

    static func resolve(
        _ text: String,
        lastVerse: (ChapterID) -> Int?,
        hasVerses: (PrayerPassage) -> Bool
    ) -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let passage = PrayerPassage.parse(trimmed, lastVerse: lastVerse) else { return .notAReference }
        return hasVerses(passage) ? .found(passage) : .notInBible
    }
}

/// The small "Sermon Notes" card on Home: Sunday mornings only.
enum SermonSunday {
    static func isSundayMorning(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard parts.weekday == 1, let hour = parts.hour else { return false }
        return (5..<14).contains(hour)
    }
}

/// Church Mode keeps the screen awake while it's on, the editor is showing
/// and the app is in front, and always puts the idle timer back as it was.
/// Pure, so the rule can be tested; the editor applies what it returns to
/// `UIApplication.shared.isIdleTimerDisabled`.
struct ScreenAwakeKeeper: Equatable, Sendable {
    /// The idle-timer setting before Church Mode took over, while it holds it.
    private(set) var savedSetting: Bool?

    var isHolding: Bool { savedSetting != nil }

    static func shouldKeepAwake(churchMode: Bool, isShowing: Bool, isActive: Bool) -> Bool {
        churchMode && isShowing && isActive
    }

    /// The value to give `isIdleTimerDisabled` now, or nil to leave it.
    mutating func update(keepAwake: Bool, current: Bool) -> Bool? {
        if keepAwake {
            if savedSetting == nil {
                savedSetting = current
                return current ? nil : true
            }
            return current ? nil : true
        }
        guard let saved = savedSetting else { return nil }
        savedSetting = nil
        return saved == current ? nil : saved
    }
}
