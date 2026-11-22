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
    /// migration 20261124000000), shown on every one of its sermons.
    var locations: [ChurchLocation] = []

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

/// One place on a church's Locations and Times: the church's own plain
/// text, `times` one line per gathering.
struct ChurchLocation: Hashable, Sendable {
    let name: String
    let address: String
    let times: String

    /// One line per gathering, blank lines left out.
    var timeLines: [String] {
        times.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Directions in Apple Maps, searched by the address; nil without one.
    var mapsURL: URL? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        return components?.url
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
    static func copyText(_ blocks: [SermonBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case let .heading(_, text, _), let .paragraph(_, text): text
            case let .quote(_, text): "\u{201C}\(text)\u{201D}"
            case let .list(_, items, ordered):
                items.enumerated().map { ordered ? "\($0.offset + 1). \($0.element)" : "\u{2022} \($0.element)" }.joined(separator: "\n")
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
