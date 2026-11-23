import Foundation

/// A church's published sermon outline (VRS-18), as `published_sermon(slug)`
/// returns it: only the published revision, never the draft. Scripture
/// text is never part of it: a reference carries verse ids in KJV numbering
/// and, for a quotation from a free Bible, only that Bible's code, so the
/// app shows the words verbatim from its own copy.
struct PublishedSermon: Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let groupID: UUID
    let church: String
    let title: String
    let speaker: String
    let series: String?
    /// "yyyy-MM-dd", the day it was preached (no time zone needed).
    let preachedOn: String?
    let location: String
    /// The outline's language: "en", "es", "pt" or "other".
    let language: String
    let cover: Cover?
    let audience: ChurchSermonAudience
    let blocks: [SermonBlock]
    let previous: ChurchSermonSummary?
    let next: ChurchSermonSummary?
    let isMember: Bool
    /// Where and when the church or ministry meets (Locations and Times,
    /// migrations 20261124000000 and 20261125000000), shown on every one of
    /// its sermons.
    var locations: [ChurchLocation] = []
    /// The published revision (1, 2…): a member's saved answers belong to
    /// the revision they filled in.
    var revision: Int = 0
    /// Fill-in-the-blank handouts (migration 20261128000000): whether the
    /// key is out for this revision, and each blank in the text's "[[n]]"
    /// markers (answers only once revealed).
    var answers: SermonAnswers = .hidden
    var blanks: [SermonBlank] = []

    /// Whether the outline is a handout with blanks to fill in.
    var hasBlanks: Bool { !blanks.isEmpty }

    struct Cover: Hashable, Sendable {
        /// The file's name in the private bucket, read only through the
        /// sermon-cover function (which checks access on every request).
        let path: String
        let alt: String
        let decorative: Bool
    }

    /// The day it was preached, at the start of that day here.
    var preachedDate: Date? { preachedOn.flatMap { Timestamp.day(from: $0) } }

    /// The verified passages, in order, each once (verse ids only), for a
    /// person's own notes.
    var passages: [PrayerPassage] {
        var seen = Set<PrayerPassage>()
        return blocks.compactMap { block -> PrayerPassage? in
            guard case let .scripture(_, reference) = block, let range = reference.range else { return nil }
            return PrayerPassage(start: range.start, end: range.end)
        }
        .filter { seen.insert($0).inserted }
    }
}

/// One place on a church's Locations and Times (migrations 20261124000000
/// and 20261125000000): the address in parts and the gatherings picked in
/// Church Studio, or plain text typed before there were parts (`address`,
/// `times`). The same rules as the web's locations.ts.
struct ChurchLocation: Hashable, Sendable {
    let name: String
    var street = ""
    var city = ""
    var region = ""
    var postalCode = ""
    var country = ""
    /// The address on one line (worked out by the database from the parts).
    var address = ""
    /// Times typed as text before there were pickers, one line each.
    var times = ""
    var gatherings: [ChurchGathering] = []

    /// Legacy time lines, blank lines left out.
    var timeLines: [String] {
        times.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The address as lines: street; "City, ST 75146"; country. Falls back
    /// to the one-line address.
    var addressLines: [String] {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let regionLine = [trim(region), trim(postalCode)].filter { !$0.isEmpty }.joined(separator: " ")
        let cityLine = [trim(city), regionLine].filter { !$0.isEmpty }.joined(separator: ", ")
        let lines = [trim(street), cityLine, trim(country)].filter { !$0.isEmpty }
        if !lines.isEmpty { return lines }
        return trim(address).isEmpty ? [] : [trim(address)]
    }

    /// The address on one line, for directions and VoiceOver.
    var oneLineAddress: String { addressLines.joined(separator: ", ") }

    /// Directions in Apple Maps, searched by the address; nil without one.
    var mapsURL: URL? {
        let address = oneLineAddress
        guard !address.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        return components?.url
    }

    /// The schedule as lines, in order: each weekday once with its times
    /// ("Sundays · 9:00 AM, 11:00 AM (Spanish)"), then dates from `today`
    /// ("yyyy-MM-dd") on, past ones left out, then any times typed as text.
    func scheduleLines(today: String, locale: Locale = .current) -> [String] {
        let valid = gatherings.filter { ChurchGathering.isTime($0.time) }
        func at(_ g: ChurchGathering) -> String {
            let time = ChurchGathering.formatTime(g.time, locale: locale)
            let note = g.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? time : "\(time) (\(note))"
        }
        var lines: [String] = []
        for day in ChurchGathering.Weekday.allCases {
            let on = valid.filter { $0.weekday == day }.sorted { $0.time < $1.time }
            if !on.isEmpty { lines.append("\(day.pluralName) · \(on.map(at).joined(separator: ", "))") }
        }
        let dates = Set(valid.compactMap(\.date).filter { $0 >= today }).sorted()
        for date in dates {
            let on = valid.filter { $0.date == date }.sorted { $0.time < $1.time }
            lines.append("\(ChurchGathering.formatDate(date, locale: locale)) · \(on.map(at).joined(separator: ", "))")
        }
        return lines + timeLines
    }
}

/// One gathering: every week on a day, or once on a date, at a time on the
/// church's own clock ("HH:mm", no time zone), with a few words of the
/// church's own.
struct ChurchGathering: Hashable, Sendable {
    enum Weekday: String, CaseIterable, Sendable {
        case sun, mon, tue, wed, thu, fri, sat

        /// "Sundays": the day as a weekly schedule names it.
        var pluralName: String {
            switch self {
            case .sun: String(localized: "Sundays")
            case .mon: String(localized: "Mondays")
            case .tue: String(localized: "Tuesdays")
            case .wed: String(localized: "Wednesdays")
            case .thu: String(localized: "Thursdays")
            case .fri: String(localized: "Fridays")
            case .sat: String(localized: "Saturdays")
            }
        }
    }

    var weekday: Weekday?
    /// "yyyy-MM-dd" for a one-time gathering.
    var date: String?
    var time: String
    var note = ""

    /// "HH:mm" on a 24-hour clock.
    static func isTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in part.count == 2 && part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    /// "yyyy-MM-dd".
    static func isDate(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2] else { return false }
        return parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    private static let utc = TimeZone(identifier: "UTC") ?? .gmt

    /// "9:00 AM" / "09:00" in the reader's language.
    static func formatTime(_ time: String, locale: Locale) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard isTime(time), parts.count == 2 else { return time }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1])) else { return time }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "Thursday, November 26, 2026" in the reader's language.
    static func formatDate(_ day: String, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let date = Timestamp.day(from: day, calendar: calendar) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum ChurchSermonAudience: String, Hashable, Sendable, Codable {
    /// Anyone with the link.
    case link
    /// Members of the church's group only.
    case members
}

/// A sermon in a list: the archive, a series' previous and next, search.
struct ChurchSermonSummary: Identifiable, Hashable, Sendable {
    let slug: String
    let title: String
    let speaker: String
    let series: String?
    let preachedOn: String?
    let audience: ChurchSermonAudience

    var id: String { slug }
    var preachedDate: Date? { preachedOn.flatMap { Timestamp.day(from: $0) } }
}

/// What a link opens.
enum ChurchSermonLookup: Hashable, Sendable {
    case sermon(PublishedSermon)
    /// Published for the church's members only, and the person isn't one
    /// (or isn't signed in). Nothing else about it is known.
    case membersOnly
    /// Never published, unpublished, hidden, deleted, or the church's
    /// sermons are switched off.
    case notFound
}

/// One block of the outline, with its text exactly as the church published it.
enum SermonBlock: Identifiable, Hashable, Sendable {
    case heading(id: String, text: String, level: Int)
    case paragraph(id: String, text: String)
    case quote(id: String, text: String)
    case list(id: String, items: [String], ordered: Bool)
    case scripture(id: String, reference: SermonReference)

    var id: String {
        switch self {
        case let .heading(id, _, _), let .paragraph(id, _), let .quote(id, _), let .list(id, _, _), let .scripture(id, _): id
        }
    }
}

/// A Scripture reference in an outline.
struct SermonReference: Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case verified, ambiguous, unlinked
    }

    /// As the pastor wrote it ("Jn 3:16", "Juan 3,16").
    let raw: String
    let start: VerseID?
    let end: VerseID?
    let status: Status
    /// The translation the pastor named, as written ("NIV", "RVR1960").
    let label: String?
    /// A quotation readers show from their own copy: KJV, WEB, ASV, RV1909
    /// or BLIVRE. The words themselves are never published.
    let translation: String?
    /// The pastor quoted words that aren't published (another translation,
    /// or a reference that couldn't be checked).
    let quoteWithheld: Bool

    /// The verses it links to: only a verified reference links.
    var range: StudyRange? {
        guard status == .verified, let start else { return nil }
        return StudyRange(start: start, end: end ?? start)
    }
}

/// A heading and what follows it, for Copy and the section list.
struct SermonOutlineSection: Identifiable, Hashable, Sendable {
    /// The heading's block id, or "start" for anything before the first heading.
    let id: String
    let title: String?
    let blocks: [SermonBlock]
}

/// The outline's pure helpers, the same as the guest page's (web/src/lib/outline.ts).
enum SermonOutline {
    /// Splits the outline at each heading.
    static func sections(_ blocks: [SermonBlock]) -> [SermonOutlineSection] {
        var out: [(id: String, title: String?, blocks: [SermonBlock])] = []
        for block in blocks {
            if case let .heading(id, text, _) = block {
                out.append((id, text, [block]))
            } else if out.isEmpty {
                out.append(("start", nil, [block]))
            } else {
                out[out.count - 1].blocks.append(block)
            }
        }
        return out.map { SermonOutlineSection(id: $0.id, title: $0.title, blocks: $0.blocks) }
    }

    /// What Copy puts on the clipboard: the church's words exactly as
    /// published, one block per paragraph; a reference as the pastor typed
    /// it, never verse text.
    static func copyText(_ blocks: [SermonBlock], blanks: [SermonBlank] = []) -> String {
        let known = Set(blanks.map(\.n))
        let words = { (text: String) in SermonBlanks.filled(text, known: known.contains) }
        return blocks.map { block -> String in
            switch block {
            case let .heading(_, text, _), let .paragraph(_, text): words(text)
            case let .quote(_, text): "\u{201C}\(text)\u{201D}"
            case let .list(_, items, ordered):
                items.enumerated().map { ordered ? "\($0.offset + 1). \(words($0.element))" : "\u{2022} \(words($0.element))" }.joined(separator: "\n")
            case let .scripture(_, reference):
                reference.label.map { "\(reference.raw) (\($0))" } ?? reference.raw
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }
}

/// A church found by name (only churches that chose to be listed), with
/// its latest sermons anyone with the link may read.
struct SermonChurch: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sermons: [ChurchSermonSummary]
}
