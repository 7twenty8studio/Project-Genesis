import Foundation

/// A period of the biblical story on the timeline (Creation, Noah, … Revelation).
struct Era: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    /// False for Creation and Noah, which are shown in order without dates.
    let isDated: Bool
    let firstVerse: VerseID
}

/// Something that happens in the biblical narrative, placed on the timeline.
struct TimelineEvent: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let eraID: String
    /// Astronomical year (0 = 1 BC); nil where the app shows no date.
    let year: Int?
    let firstVerse: VerseID?
    let lastVerse: VerseID?

    /// "c. 1490 BC", "c. AD 30", or nil. Dates are approximate and follow a
    /// traditional chronology.
    var yearLabel: String? {
        year.map(Self.label(forYear:))
    }

    static func label(forYear year: Int) -> String {
        // Years as plain text: an Int would be formatted with a grouping separator ("c. 1,491 BC").
        year <= 0 ? String(localized: "c. \(String(1 - year)) BC", comment: "Approximate year before Christ") : String(localized: "c. AD \(String(year))", comment: "Approximate year after Christ")
    }

    var reference: PassageReference? {
        guard let firstVerse else { return nil }
        return PassageReference(verse: firstVerse)
    }
}

/// A person, as listed in search results and relationship rows.
struct PersonSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// Other names, e.g. "Saul" for Paul; may be empty.
    let alsoCalled: String
    let verseCount: Int
}

struct Person: Identifiable, Hashable, Sendable {
    let summary: PersonSummary
    let gender: String
    /// From Easton's Bible Dictionary (1897, public domain). Not Scripture.
    let biography: String
    let birthYear: Int?
    let deathYear: Int?
    /// e.g. "Tribe of Levi"; may be empty.
    let group: String
    let firstVerse: VerseID?

    var id: Int { summary.id }
    var name: String { summary.name }

    /// "c. 1085 BC – c. 1015 BC", or nil when neither date is known.
    var lifespan: String? {
        switch (birthYear, deathYear) {
        case let (born?, died?): String(localized: "\(TimelineEvent.label(forYear: born)) – \(TimelineEvent.label(forYear: died))", comment: "Lifespan: birth year – death year")
        case let (born?, nil): String(localized: "Born \(TimelineEvent.label(forYear: born))")
        case let (nil, died?): String(localized: "Died \(TimelineEvent.label(forYear: died))")
        case (nil, nil): nil
        }
    }
}

enum RelationKind: String, CaseIterable, Sendable {
    case father, mother, partner, child, sibling

    var title: String {
        switch self {
        case .father: String(localized: "Father")
        case .mother: String(localized: "Mother")
        case .partner: String(localized: "Spouse")
        case .child: String(localized: "Children")
        case .sibling: String(localized: "Siblings")
        }
    }
}

/// A person's immediate family, for the family tree.
struct Family: Sendable, Equatable {
    var parents: [PersonSummary] = []
    var partners: [PersonSummary] = []
    var siblings: [PersonSummary] = []
    var children: [PersonSummary] = []

    var isEmpty: Bool { parents.isEmpty && partners.isEmpty && siblings.isEmpty && children.isEmpty }
}

struct PlaceSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// "City", "Region", "Mountain", …
    let kind: String
    let latitude: Double?
    let longitude: Double?
    let verseCount: Int
    /// How sure scholars are of the location, 0–1000 (OpenBible.info); nil
    /// when unknown.
    var confidence: Int? = nil

    var isMapped: Bool { latitude != nil && longitude != nil }
    var certainty: PlaceCertainty { PlaceCertainty(confidence: confidence) }
}

/// How sure we can be where a place was, from OpenBible.info's confidence
/// score, which weighs 70+ atlases, Bible dictionaries and commentaries.
enum PlaceCertainty: Sendable, CaseIterable {
    /// Scholars agree (Jerusalem, Corinth, Capernaum).
    case known
    /// Most scholars put it here (Elim, Rameses).
    case likely
    /// Debated or unknown; the pin is one suggestion (Mount Sinai, Emmaus).
    case uncertain

    init(confidence: Int?) {
        switch confidence ?? 0 {
        case 750...: self = .known
        case 500..<750: self = .likely
        default: self = .uncertain
        }
    }

    var title: String {
        switch self {
        case .known: String(localized: "Known location")
        case .likely: String(localized: "Likely location")
        case .uncertain: String(localized: "Uncertain location")
        }
    }

    var explanation: String {
        switch self {
        case .known: String(localized: "Scholars agree on where this was.")
        case .likely: String(localized: "Most scholars place it here, though not all.")
        case .uncertain: String(localized: "Where this was is debated or unknown. The pin shows one suggested site.")
        }
    }

    var symbol: String {
        switch self {
        case .known: "checkmark.seal"
        case .likely: "circle.dashed"
        case .uncertain: "questionmark.circle"
        }
    }
}

struct Place: Identifiable, Hashable, Sendable {
    let summary: PlaceSummary
    let aliases: String
    /// From Easton's Bible Dictionary (public domain). Not Scripture.
    let description: String
    /// False where the location is uncertain.
    let isPrecise: Bool
    let firstVerse: VerseID?

    var id: Int { summary.id }
    var name: String { summary.name }
}

/// A journey drawn on the map: Paul's journeys and a traditional Exodus route.
struct Route: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let passage: String
    let firstVerse: VerseID
    let stops: [PlaceSummary]
}

/// How many times a book mentions someone or somewhere.
struct BookMentions: Identifiable, Hashable, Sendable {
    let book: BibleBook
    let count: Int
    let firstVerse: VerseID
    var id: Int { book.id }
}
