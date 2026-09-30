import Foundation

/// People, places, events and routes for the timeline, maps and character
/// explorer, read from the bundled Study.sqlite.
///
/// Data: Theographic Bible Metadata (CC BY-SA 4.0), with coordinates from
/// OpenBible.info (CC BY 4.0) and descriptions from Easton's Bible Dictionary
/// (public domain). It holds verse ids only, never Scripture text.
final class StudyRepository: Sendable {
    static let attribution = "People, places and events from Theographic Bible Metadata (CC BY-SA 4.0). Map locations from OpenBible.info (CC BY 4.0). Descriptions from Easton's Bible Dictionary (1897)."
    static let chronologyNote = "Dates are approximate and follow a traditional chronology. Events before Abraham are shown in order without dates."

    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    /// The bundled database, or nil if it's missing from the build.
    static func bundled(in bundle: Bundle = .main) -> StudyRepository? {
        bundle.url(forResource: "Study", withExtension: "sqlite").flatMap { try? StudyRepository(url: $0) }
    }

    // MARK: Timeline

    func eras() throws -> [Era] {
        try database.query("SELECT id, title, summary, dated, first_verse FROM eras ORDER BY sort") {
            Era(id: $0.text(0), title: $0.text(1), summary: $0.text(2), isDated: $0.bool(3), firstVerse: VerseID(rawValue: $0.int(4)))
        }
    }

    func events(inEra era: String) throws -> [TimelineEvent] {
        try database.query("\(Self.eventColumns) WHERE era = ? ORDER BY sort_key, id", [.text(era)], map: Self.event)
    }

    func event(id: Int) throws -> TimelineEvent? {
        try database.query("\(Self.eventColumns) WHERE id = ?", [.int(id)], map: Self.event).first
    }

    /// Chapters the event is told in, in canonical order.
    func chapters(forEvent id: Int) throws -> [ChapterID] {
        try database.query(
            "SELECT DISTINCT verse / 1000 FROM event_verses WHERE event_id = ? ORDER BY 1",
            [.int(id)]
        ) { ChapterID(book: $0.int(0) / 1000, chapter: $0.int(0) % 1000) }
    }

    func people(inEvent id: Int) throws -> [PersonSummary] {
        try database.query(
            "\(Self.personColumns) JOIN event_people e ON e.person_id = p.id WHERE e.event_id = ? ORDER BY p.verse_count DESC",
            [.int(id)], map: Self.personSummary
        )
    }

    func places(inEvent id: Int) throws -> [PlaceSummary] {
        try database.query(
            "\(Self.placeColumns) JOIN event_places e ON e.place_id = p.id WHERE e.event_id = ? ORDER BY p.verse_count DESC",
            [.int(id)], map: Self.placeSummary
        )
    }

    func events(forPerson id: Int) throws -> [TimelineEvent] {
        try database.query(
            "SELECT ev.id, ev.title, ev.era, ev.year, ev.first_verse, ev.last_verse FROM events ev JOIN event_people e ON e.event_id = ev.id WHERE e.person_id = ? ORDER BY ev.sort_key",
            [.int(id)], map: Self.event
        )
    }

    func events(atPlace id: Int) throws -> [TimelineEvent] {
        try database.query(
            "SELECT ev.id, ev.title, ev.era, ev.year, ev.first_verse, ev.last_verse FROM events ev JOIN event_places e ON e.event_id = ev.id WHERE e.place_id = ? ORDER BY ev.sort_key",
            [.int(id)], map: Self.event
        )
    }

    /// Events told in a chapter, for the reader's study panel.
    func events(inChapter chapter: ChapterID) throws -> [TimelineEvent] {
        let range = chapter.verseRange
        return try database.query(
            "SELECT DISTINCT ev.id, ev.title, ev.era, ev.year, ev.first_verse, ev.last_verse, ev.sort_key FROM events ev JOIN event_verses v ON v.event_id = ev.id WHERE v.verse BETWEEN ? AND ? ORDER BY ev.sort_key",
            [.int(range.lowerBound), .int(range.upperBound)], map: Self.event
        )
    }

    // MARK: People

    /// People whose name (or other name) starts with the text; the best known first.
    func searchPeople(_ text: String, limit: Int = 50) throws -> [PersonSummary] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return try notablePeople(limit: limit) }
        let pattern = Self.likePrefix(trimmed)
        return try database.query(
            "\(Self.personColumns) WHERE p.name LIKE ? ESCAPE '\\' OR p.also_called LIKE ? ESCAPE '\\' OR p.also_called LIKE ? ESCAPE '\\' ORDER BY p.verse_count DESC LIMIT ?",
            [.text(pattern), .text(pattern), .text("%, " + pattern), .int(limit)], map: Self.personSummary
        )
    }

    /// The most-mentioned people, for the explorer's opening list.
    func notablePeople(limit: Int = 50) throws -> [PersonSummary] {
        try database.query("\(Self.personColumns) ORDER BY p.verse_count DESC LIMIT ?", [.int(limit)], map: Self.personSummary)
    }

    func person(id: Int) throws -> Person? {
        try database.query(
            "SELECT p.id, p.name, p.also_called, p.verse_count, p.gender, p.bio, p.birth_year, p.death_year, p.tribe, p.first_verse FROM people p WHERE p.id = ?",
            [.int(id)]
        ) {
            Person(
                summary: Self.personSummary($0),
                gender: $0.text(4),
                biography: $0.text(5),
                birthYear: $0.optionalInt(6),
                deathYear: $0.optionalInt(7),
                group: $0.text(8),
                firstVerse: $0.optionalInt(9).map(VerseID.init(rawValue:))
            )
        }.first
    }

    func family(ofPerson id: Int) throws -> Family {
        let rows = try database.query(
            "SELECT r.kind, p.id, p.name, p.also_called, p.verse_count FROM relations r JOIN people p ON p.id = r.other_id WHERE r.person_id = ? ORDER BY p.verse_count DESC",
            [.int(id)]
        ) { row -> (RelationKind?, PersonSummary) in
            (RelationKind(rawValue: row.text(0)),
             PersonSummary(id: row.int(1), name: row.text(2), alsoCalled: row.text(3), verseCount: row.int(4)))
        }
        var family = Family()
        for (kind, person) in rows {
            switch kind {
            case .father, .mother: family.parents.append(person)
            case .partner: family.partners.append(person)
            case .sibling: family.siblings.append(person)
            case .child: family.children.append(person)
            case nil: continue
            }
        }
        // Fathers before mothers, as in the genealogies.
        let fathers = Set(rows.filter { $0.0 == .father }.map(\.1.id))
        family.parents.sort { fathers.contains($0.id) && !fathers.contains($1.id) }
        return family
    }

    /// Books that mention the person, in canonical order.
    func books(forPerson id: Int) throws -> [BookMentions] {
        try database.query(
            "SELECT verse / 1000000, COUNT(*) FROM person_verses WHERE person_id = ? GROUP BY 1 ORDER BY 1",
            [.int(id)]
        ) { BookMentions(book: .withNumber($0.int(0)), count: $0.int(1)) }
    }

    func verses(forPerson id: Int, limit: Int = 200) throws -> [VerseID] {
        try database.query(
            "SELECT verse FROM person_verses WHERE person_id = ? ORDER BY verse LIMIT ?",
            [.int(id), .int(limit)]
        ) { VerseID(rawValue: $0.int(0)) }
    }

    /// People mentioned in a chapter, the most prominent first.
    func people(inChapter chapter: ChapterID, limit: Int = 30) throws -> [PersonSummary] {
        let range = chapter.verseRange
        return try database.query(
            "\(Self.personColumns) WHERE p.id IN (SELECT person_id FROM person_verses WHERE verse BETWEEN ? AND ?) ORDER BY p.verse_count DESC LIMIT ?",
            [.int(range.lowerBound), .int(range.upperBound), .int(limit)], map: Self.personSummary
        )
    }

    // MARK: Places

    func place(id: Int) throws -> Place? {
        try database.query(
            "SELECT p.id, p.name, p.kind, p.latitude, p.longitude, p.verse_count, p.aliases, p.bio, p.precise, p.first_verse FROM places p WHERE p.id = ?",
            [.int(id)]
        ) {
            Place(
                summary: Self.placeSummary($0),
                aliases: $0.text(6),
                description: $0.text(7),
                isPrecise: $0.bool(8),
                firstVerse: $0.optionalInt(9).map(VerseID.init(rawValue:))
            )
        }.first
    }

    /// Places with coordinates, the most-mentioned first.
    func mappedPlaces(minimumMentions: Int = 1, limit: Int = 2000) throws -> [PlaceSummary] {
        try database.query(
            "\(Self.placeColumns) WHERE p.latitude IS NOT NULL AND p.verse_count >= ? ORDER BY p.verse_count DESC LIMIT ?",
            [.int(minimumMentions), .int(limit)], map: Self.placeSummary
        )
    }

    func searchPlaces(_ text: String, limit: Int = 50) throws -> [PlaceSummary] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return try mappedPlaces(minimumMentions: 10, limit: limit) }
        let pattern = Self.likePrefix(trimmed)
        return try database.query(
            "\(Self.placeColumns) WHERE p.name LIKE ? ESCAPE '\\' OR p.aliases LIKE ? ESCAPE '\\' ORDER BY p.verse_count DESC LIMIT ?",
            [.text(pattern), .text("%" + pattern), .int(limit)], map: Self.placeSummary
        )
    }

    /// Mapped places mentioned in a chapter.
    func places(inChapter chapter: ChapterID, limit: Int = 30) throws -> [PlaceSummary] {
        let range = chapter.verseRange
        return try database.query(
            "\(Self.placeColumns) WHERE p.latitude IS NOT NULL AND p.id IN (SELECT place_id FROM place_verses WHERE verse BETWEEN ? AND ?) ORDER BY p.verse_count DESC LIMIT ?",
            [.int(range.lowerBound), .int(range.upperBound), .int(limit)], map: Self.placeSummary
        )
    }

    func verses(forPlace id: Int, limit: Int = 200) throws -> [VerseID] {
        try database.query(
            "SELECT verse FROM place_verses WHERE place_id = ? ORDER BY verse LIMIT ?",
            [.int(id), .int(limit)]
        ) { VerseID(rawValue: $0.int(0)) }
    }

    // MARK: Routes

    func routes() throws -> [Route] {
        let headers = try database.query("SELECT id, title, passage, first_verse FROM routes ORDER BY sort") {
            ($0.text(0), $0.text(1), $0.text(2), VerseID(rawValue: $0.int(3)))
        }
        return try headers.map { id, title, passage, first in
            let stops = try database.query(
                "SELECT p.id, p.name, p.kind, p.latitude, p.longitude, p.verse_count FROM route_stops s JOIN places p ON p.id = s.place_id WHERE s.route_id = ? ORDER BY s.position",
                [.text(id)], map: Self.placeSummary
            )
            return Route(id: id, title: title, passage: passage, firstVerse: first, stops: stops)
        }
    }

    // MARK: Rows

    private static let eventColumns = "SELECT id, title, era, year, first_verse, last_verse FROM events"
    private static let personColumns = "SELECT p.id, p.name, p.also_called, p.verse_count FROM people p"
    private static let placeColumns = "SELECT p.id, p.name, p.kind, p.latitude, p.longitude, p.verse_count FROM places p"

    private static func event(_ row: SQLiteDatabase.Row) -> TimelineEvent {
        TimelineEvent(
            id: row.int(0),
            title: row.text(1),
            eraID: row.text(2),
            year: row.optionalInt(3),
            firstVerse: row.optionalInt(4).map(VerseID.init(rawValue:)),
            lastVerse: row.optionalInt(5).map(VerseID.init(rawValue:))
        )
    }

    private static func personSummary(_ row: SQLiteDatabase.Row) -> PersonSummary {
        PersonSummary(id: row.int(0), name: row.text(1), alsoCalled: row.text(2), verseCount: row.int(3))
    }

    private static func placeSummary(_ row: SQLiteDatabase.Row) -> PlaceSummary {
        PlaceSummary(
            id: row.int(0),
            name: row.text(1),
            kind: row.text(2),
            latitude: row.optionalDouble(3),
            longitude: row.optionalDouble(4),
            verseCount: row.int(5)
        )
    }

    /// "Ab" -> "Ab%", with LIKE wildcards in the text escaped.
    static func likePrefix(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return escaped + "%"
    }
}
