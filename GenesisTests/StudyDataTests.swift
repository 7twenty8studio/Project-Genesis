import Foundation
import Testing
@testable import Genesis

/// The bundled Study.sqlite: timeline, people, places and routes.
@Suite("Study data")
struct StudyDataTests {
    private func repository() throws -> StudyRepository {
        let url = try #require(Bundle.main.url(forResource: "Study", withExtension: "sqlite"))
        return try StudyRepository(url: url)
    }

    @Test func erasFollowThePRDOrder() throws {
        let eras = try repository().eras()
        let titles = eras.map(\.title)
        #expect(titles == ["Creation", "Noah", "Abraham", "Moses", "Joshua", "Judges", "Kings", "Prophets", "Jesus", "Acts", "Letters", "Revelation"])
        let undated = eras.filter { !$0.isDated }.map(\.id)
        #expect(undated == ["creation", "noah"])
    }

    @Test func eventsBeforeAbrahamHaveNoDates() throws {
        let study = try repository()
        let creation = try study.events(inEra: "creation")
        let noah = try study.events(inEra: "noah")
        #expect(!creation.isEmpty)
        let dated = (creation + noah).filter { $0.year != nil }
        #expect(dated.isEmpty)
        let jesus = try study.events(inEra: "jesus")
        let birth = jesus.first { $0.title == "Birth of Jesus" }
        #expect(birth?.yearLabel?.hasSuffix("BC") == true)
    }

    @Test func eventsAreInChronologicalOrder() throws {
        let events = try repository().events(inEra: "kings")
        let years = events.compactMap(\.year)
        #expect(years == years.sorted())
    }

    @Test func yearLabels() {
        #expect(TimelineEvent.label(forYear: -1490) == "c. 1491 BC")
        #expect(TimelineEvent.label(forYear: 0) == "c. 1 BC")
        #expect(TimelineEvent.label(forYear: 30) == "c. AD 30")
    }

    @Test func davidsFamilyAndBooks() throws {
        let study = try repository()
        let found = try study.searchPeople("David")
        let david = try #require(found.first)
        #expect(david.name == "David")
        let family = try study.family(ofPerson: david.id)
        let parents = family.parents.map(\.name)
        let children = family.children.map(\.name)
        #expect(parents.contains("Jesse"))
        #expect(children.contains("Solomon"))
        let books = try study.books(forPerson: david.id).map(\.book.name)
        #expect(books.contains("1 Samuel"))
        #expect(books.contains("Psalms"))
        let loaded = try study.person(id: david.id)
        let person = try #require(loaded)
        #expect(!person.biography.isEmpty)
    }

    @Test func searchFindsOtherNames() throws {
        let study = try repository()
        let results = try study.searchPeople("Saul")
        let names = results.map(\.name)
        #expect(names.contains("Paul"), "Paul is also called Saul")
        let percent = try study.searchPeople("%")
        #expect(percent.isEmpty, "LIKE wildcards are matched literally")
    }

    @Test func godIsNotListedAsAPerson() throws {
        let study = try repository()
        let people = try study.people(inChapter: ChapterID(book: 1, chapter: 1))
        let names = people.map(\.name)
        #expect(!names.contains("God"))
    }

    @Test func jerusalemIsMapped() throws {
        let study = try repository()
        let results = try study.searchPlaces("Jerusalem")
        let jerusalem = try #require(results.first)
        #expect(jerusalem.isMapped)
        let latitude = try #require(jerusalem.latitude)
        let longitude = try #require(jerusalem.longitude)
        #expect(abs(latitude - 31.78) < 0.1)
        #expect(abs(longitude - 35.23) < 0.1)
    }

    @Test func routesHaveMappedStops() throws {
        let routes = try repository().routes()
        let titles = routes.map(\.title)
        #expect(titles.contains("Paul's First Journey"))
        let hasExodus = titles.contains { $0.hasPrefix("The Exodus") }
        #expect(hasExodus)
        let unmapped = routes.flatMap(\.stops).filter { !$0.isMapped }
        #expect(unmapped.isEmpty)
        let first = try #require(routes.first)
        #expect(first.stops.first?.name == "Antioch (Syria)")
    }

    @Test func chapterContext() throws {
        let study = try repository()
        let acts13 = ChapterID(book: 44, chapter: 13)
        let places = try study.places(inChapter: acts13).map(\.name)
        #expect(places.contains("Paphos"))
        let matthew2 = ChapterID(book: 40, chapter: 2)
        let events = try study.events(inChapter: matthew2).map(\.title)
        let hasWiseMen = events.contains { $0.contains("Wise Men") }
        #expect(hasWiseMen)
    }
}
