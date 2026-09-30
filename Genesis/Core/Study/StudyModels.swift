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
        year <= 0 ? "c. \(1 - year) BC" : "c. AD \(year)"
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
        case let (born?, died?): "\(TimelineEvent.label(forYear: born)) – \(TimelineEvent.label(forYear: died))"
        case let (born?, nil): "Born \(TimelineEvent.label(forYear: born))"
        case let (nil, died?): "Died \(TimelineEvent.label(forYear: died))"
        case (nil, nil): nil
        }
    }
}

enum RelationKind: String, CaseIterable, Sendable {
    case father, mother, partner, child, sibling

    var title: String {
        switch self {
        case .father: "Father"
        case .mother: "Mother"
        case .partner: "Spouse"
        case .child: "Children"
        case .sibling: "Siblings"
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

    var isMapped: Bool { latitude != nil && longitude != nil }
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
    var id: Int { book.id }
}
