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

    @Test func placesSayHowCertainTheirLocationIs() throws {
        let study = try repository()
        let jerusalem = try #require(try study.searchPlaces("Jerusalem").first { $0.name == "Jerusalem" })
        #expect(jerusalem.certainty == .known)
        let sinai = try #require(try study.searchPlaces("Mount Sinai").first { $0.name == "Mount Sinai" })
        #expect(sinai.certainty == .uncertain)
        let elimSummary = try #require(try study.searchPlaces("Elim").first { $0.name == "Elim" })
        let elim = try #require(try study.place(id: elimSummary.id))
        #expect(elim.summary.certainty == .likely)
        // The Exodus route mixes all three; Paul's journeys are well known.
        let routes = try study.routes()
        let exodus = try #require(routes.first { $0.id == "exodus" })
        #expect(Set(exodus.stops.map(\.certainty)) == Set(PlaceCertainty.allCases))
        let rome = try #require(routes.first { $0.id == "paul-rome" })
        #expect(rome.stops.filter { $0.certainty == .known }.count >= rome.stops.count - 1)
    }

    @Test func certaintyThresholds() {
        #expect(PlaceCertainty(confidence: 1000) == .known)
        #expect(PlaceCertainty(confidence: 750) == .known)
        #expect(PlaceCertainty(confidence: 749) == .likely)
        #expect(PlaceCertainty(confidence: 500) == .likely)
        #expect(PlaceCertainty(confidence: 499) == .uncertain)
        #expect(PlaceCertainty(confidence: nil) == .uncertain)
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

    @Test func exodusFollowsTheTraditionalRoute() throws {
        let exodus = try #require(try repository().routes().first { $0.id == "exodus" })
        let names = exodus.stops.map(\.name)
        #expect(names.first == "Rameses")
        #expect(names.last == "Abel-shittim")
        for stop in ["Succoth", "Pi-hahiroth", "Marah", "Elim", "Mount Sinai", "Kadesh-barnea", "Mount Hor", "Mount Nebo"] {
            #expect(names.contains(stop))
        }
        // The Succoth of Exodus 12:37 is in Egypt, not Jacob's by the Jordan.
        let succoth = try #require(exodus.stops.first { $0.name == "Succoth" })
        let longitude = try #require(succoth.longitude)
        #expect(longitude < 33)
        // Around Edom (Numbers 21:4): the line goes east of Mount Hor.
        let hor = try #require(exodus.stops.first { $0.name == "Mount Hor" })
        let horLongitude = try #require(hor.longitude)
        let east = exodus.path.filter { $0.longitude > horLongitude + 0.4 }
        #expect(!east.isEmpty)
    }

    @Test func routePathsRunThroughEveryStop() throws {
        for route in try repository().routes() {
            #expect(route.path.count >= route.stops.count)
            let path = Set(route.path)
            for stop in route.stops {
                let latitude = try #require(stop.latitude)
                let longitude = try #require(stop.longitude)
                #expect(path.contains(RoutePoint(latitude: latitude, longitude: longitude)))
            }
        }
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

/// Spanish and Portuguese names from the translations table, falling back to English.
@Suite("Study data in Spanish and Portuguese")
struct StudyTranslationTests {
    private func repository(_ language: String?) throws -> StudyRepository {
        let url = try #require(Bundle.main.url(forResource: "Study", withExtension: "sqlite"))
        return try StudyRepository(url: url, language: language)
    }

    @Test func englishAndUnknownLanguagesKeepTheEnglish() throws {
        #expect(try repository(nil).language == nil)
        #expect(try repository("en").language == nil)
        #expect(try repository("fr").language == nil)
        let moses = try #require(try repository("en").searchPeople("Moses").first)
        #expect(moses.name == "Moses")
    }

    @Test(arguments: [("es", "Moisés", "Jerusalén", "Primer viaje de Pablo"), ("pt", "Moisés", "Jerusalém", "Primeira viagem de Paulo")])
    func namesTitlesAndJourneys(language: String, moses: String, jerusalem: String, journey: String) throws {
        let study = try repository(language)
        #expect(study.language == language)
        // Found by the translated name without its accent, and by the English one.
        let found = try #require(try study.searchPeople("moise").first)
        #expect(found.name == moses)
        #expect(try study.searchPeople("Moses").first?.id == found.id)
        let place = try #require(try study.searchPlaces(jerusalem).first)
        #expect(place.name == jerusalem)
        #expect(try study.place(id: place.id)?.name == jerusalem)
        #expect(try study.routes().first?.title == journey)
        // Easton's biographies and place descriptions are translated (each
        // passed bios.py's check) and say so; English keeps the original.
        let person = try #require(try study.person(id: found.id))
        let english = try #require(try repository(nil).person(id: found.id))
        #expect(!english.biographyIsTranslated)
        #expect(person.biographyIsTranslated)
        #expect(person.biography != english.biography)
        #expect(!person.biography.isEmpty)
        let city = try #require(try study.place(id: place.id))
        let englishCity = try #require(try repository(nil).place(id: place.id))
        #expect(city.descriptionIsTranslated)
        #expect(!englishCity.descriptionIsTranslated)
        #expect(city.description != englishCity.description)
    }

    @Test(arguments: ["es", "pt"])
    func everyEventAndEraHasATitle(language: String) throws {
        let study = try repository(language)
        let english = try repository(nil)
        let eras = try study.eras()
        #expect(eras.count == 12)
        for era in eras {
            let original = try #require(try english.eras().first { $0.id == era.id })
            #expect(era.title != original.title || era.id == "abraham" || era.id == "jesus")
            #expect(era.summary != original.summary)
            for event in try study.events(inEra: era.id) {
                let title = try #require(try english.event(id: event.id)).title
                #expect(event.title != title, "\(language) event \(event.id) \(title)")
            }
        }
    }

    @Test func otherNamesLeaveOutTheNameItself() {
        #expect(OtherNames.distinct("Lucas", besides: "Lucas") == "")
        #expect(OtherNames.distinct("Elias", besides: "Elías") == "")
        #expect(OtherNames.distinct("Asaf, Abiasaf, asaf", besides: "Asaf (levita)") == "Abiasaf")
        #expect(OtherNames.distinct("Saul", besides: "Paul") == "Saul")
        #expect(OtherNames.distinct("", besides: "Paul") == "")
        #expect(PersonSummary(id: 1, name: "Lucas", alsoCalled: "Lucas", verseCount: 3).alsoCalled.isEmpty)
    }

    @Test(arguments: [("es", 85, "Nacimiento de Jacob y Esaú"), ("pt", 85, "Nascimento de Jacó e Esaú"), ("es", 220, "Profecías de Miqueas"), ("pt", 220, "Profecias de Miqueias")])
    func eventTitlesNamePeopleAsTheBibleDoes(language: String, id: Int, title: String) throws {
        #expect(try repository(language).event(id: id)?.title == title)
    }

    @Test func groupLabelsAreShownOneByOne() {
        let person = Person(
            summary: PersonSummary(id: 1, name: "Judas", alsoCalled: "", verseCount: 1),
            gender: "", biography: "", birthYear: nil, deathYear: nil,
            group: "Tribe of Judah,Apostles", firstVerse: nil
        )
        #expect(person.groupTitle == "\(PersonGroup.title("Tribe of Judah")) \u{00B7} \(PersonGroup.title("Apostles"))")
        #expect(PersonGroup.title("Something new") == "Something new")
    }
}
