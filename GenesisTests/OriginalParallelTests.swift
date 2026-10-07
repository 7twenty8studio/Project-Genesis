import Foundation
import Testing
@testable import Genesis

/// The Original parallel Bible: verse alignment between Bibles and the
/// Hebrew/Greek word data (KJV numbering), each Bible's Greek edition,
/// joining words verbatim, morphology, edition marks and the free preview.
@Suite("Original parallel Bible")
struct OriginalParallelTests {
    private func wordStudy() throws -> WordStudyRepository {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        return try WordStudyRepository(url: url)
    }

    private func bible(_ translation: Translation) throws -> BibleRepository {
        let url = try #require(Bundle.main.url(forResource: translation.id, withExtension: "sqlite"))
        return try BibleRepository(translation: translation, url: url)
    }

    /// The rows for a chapter, built the way `OriginalParallelView` builds them.
    private func rows(_ translation: Translation, _ chapter: ChapterID, limit: Int? = nil) throws -> [OriginalParallelRow] {
        let map = try #require(OriginalVersification.map(for: translation.id))
        let edition = try #require(translation.greekSource).edition
        let verses = try bible(translation).chapter(chapter).verses
        let needed = OriginalParallel.kjvVerses(for: verses.map(\.id), map: map)
        let words = try wordStudy().words(inVerses: needed, greek: edition)
        return OriginalParallel.rows(verses: verses, map: map, words: words, limit: limit)
    }

    private func verse(_ book: Int, _ chapter: Int, _ verse: Int) -> VerseID {
        VerseID(book: book, chapter: chapter, verse: verse)
    }

    // MARK: Which Bibles

    @Test func onlyCheckedBiblesOfferTheOriginal() {
        let kjv = OriginalVersification.supports(.kjv)
        let web = OriginalVersification.supports(.web)
        let asv = OriginalVersification.supports(.asv)
        let reinaValera = OriginalVersification.map(for: "RV1909") != nil
        let unchecked = OriginalVersification.map(for: "BSB") == nil
        #expect(kjv && web && asv && reinaValera)
        #expect(unchecked, "A Bible whose numbering hasn't been checked shows no original text")
    }

    // MARK: Alignment

    @Test func psalmTitlesBelongToVerseOne() throws {
        let rows = try rows(.kjv, ChapterID(book: 19, chapter: 51))
        let first = try #require(rows.first)
        let opening = first.words.first?.strongs
        let wash = rows[1].words.count
        #expect(first.number == 1)
        // The title (Hebrew 51:1–2) comes first, then "Have mercy upon me".
        #expect(opening == "H5329")
        #expect(first.words.count == 19)
        #expect(wash == 5)
        #expect(rows.count == 19)
    }

    @Test func malachiFourIsHebrewThreeNineteen() throws {
        let study = try wordStudy()
        let malachi = try study.words(in: verse(39, 4, 1))
        let hebrewNumbering = try study.words(in: verse(39, 3, 19))
        let rows = try rows(.asv, ChapterID(book: 39, chapter: 4))
        let opening = malachi.first?.text
        let everyVerse = rows.allSatisfy { !$0.words.isEmpty }
        #expect(malachi.count == 26)
        #expect(opening == "כִּֽי־")
        #expect(hebrewNumbering.isEmpty, "The KJV's Malachi 3 ends at verse 18")
        #expect(rows.count == 6)
        #expect(everyVerse)
    }

    @Test func newTestamentEndingsLineUp() throws {
        let study = try wordStudy()
        let revelation = try study.words(in: verse(66, 22, 21))
        let lastWord = revelation.last?.text
        let thirdJohn = try rows(.kjv, ChapterID(book: 64, chapter: 1))
        let markEnding = try rows(.kjv, ChapterID(book: 41, chapter: 16))
        let longerEnding = markEnding.filter { (9...20).contains($0.number) }
        let lastOfThirdJohn = thirdJohn.last?.words.count ?? 0
        let longerEndingHasGreek = longerEnding.allSatisfy { !$0.words.isEmpty }
        #expect(lastWord == "ἀμήν.")
        // 3 John has 14 verses in the KJV; its verse 14 holds what some Bibles number 15.
        #expect(thirdJohn.count == 14)
        #expect(lastOfThirdJohn > 0)
        // The Textus Receptus has Mark 16:9–20.
        #expect(longerEnding.count == 12)
        #expect(longerEndingHasGreek)
    }

    @Test func romansDoxologyFollowsEachBible() throws {
        let study = try wordStudy()
        let doxology = try study.words(in: verse(45, 16, 25))
        let byzantine = try study.words(in: verse(45, 16, 25), greek: .byzantine)
        let kjv = try rows(.kjv, ChapterID(book: 45, chapter: 16))
        let webFourteen = try rows(.web, ChapterID(book: 45, chapter: 14))
        let webSixteen = try rows(.web, ChapterID(book: 45, chapter: 16))
        let kjvTwentyFive = kjv.first { $0.number == 25 }?.words
        let webTwentyFour = webFourteen.first { $0.number == 24 }?.words
        let webEmpty = webSixteen.first { $0.number == 25 }
        #expect(!doxology.isEmpty)
        #expect(kjvTwentyFive == doxology)
        // The WEB prints the doxology (from the Byzantine text) at 14:24–26 and leaves 16:25 empty.
        #expect(webTwentyFour == byzantine)
        #expect(byzantine.map(\.text) == doxology.map(\.text))
        #expect(webFourteen.count == 26)
        #expect(webEmpty?.text.isEmpty == true)
        #expect(webEmpty?.words.isEmpty == true)
    }

    @Test func reinaValeraNumberingLinesUp() {
        let map = OriginalVersification.map(for: "RV1909") ?? .kjv
        let jonah = map.alignment(of: verse(32, 2, 1)).kjv
        let jonahEnd = map.alignment(of: verse(32, 2, 10)).kjv
        let acts = map.alignment(of: verse(44, 19, 40)).kjv
        let numbers = map.alignment(of: verse(4, 13, 1)).kjv
        let job = map.alignment(of: verse(18, 39, 30)).kjv
        let jobForty = map.alignment(of: verse(18, 40, 1)).kjv
        let corinthians = map.alignment(of: verse(47, 13, 13)).kjv
        let judges = map.alignment(of: verse(7, 14, 19))
        let john = map.alignment(of: verse(43, 3, 16)).kjv
        #expect(jonah == [verse(32, 1, 17)])
        #expect(jonahEnd == [verse(32, 2, 9), verse(32, 2, 10)])
        #expect(acts == [verse(44, 19, 40), verse(44, 19, 41)])
        #expect(numbers == [verse(4, 12, 16)])
        #expect(job.first == verse(18, 39, 27))
        #expect(job.last == verse(18, 40, 5))
        #expect(job.count == 9)
        #expect(jobForty == [verse(18, 40, 6)])
        #expect(corinthians == [verse(47, 13, 14)])
        #expect(judges.verses == [verse(7, 14, 18), verse(7, 14, 19)])
        #expect(judges.kjv == [verse(7, 14, 18)])
        #expect(john == [verse(43, 3, 16)])
    }

    @Test("No KJV verse is given to two verses", arguments: ["WEB", "RV1909"])
    func noKJVVerseIsUsedTwice(translationID: String) {
        let exceptions = translationID == "WEB" ? OriginalVersification.webExceptions : OriginalVersification.reinaValera1909Exceptions
        let groups = Array(Set(exceptions))
        let kjv = groups.flatMap(\.kjv)
        let unique = Set(kjv)
        #expect(!groups.isEmpty)
        #expect(kjv.count == unique.count)
    }

    @Test func groupedVersesShowTheOriginalOnce() {
        // Two verses of a Bible holding two KJV verses divided differently.
        let map = VersificationMap(exceptions: OriginalVersification.group(book: 9, [(10, 25), (10, 26)], kjv: [(10, 25), (10, 26)]))
        let verses = (24...27).map { Verse(id: verse(9, 10, $0), text: "v\($0)", startsParagraph: false, isPoetry: false) }
        let words = Dictionary(uniqueKeysWithValues: (24...27).map { number in
            (verse(9, 10, number), [Self.word(verse(9, 10, number), "w\(number)")])
        })
        let rows = OriginalParallel.rows(verses: verses, map: map, words: words)
        let grouped = rows[1].words.map(\.text)
        let numbers = rows.map(\.number)
        #expect(numbers == [24, 25, 26, 27])
        #expect(grouped == ["w25", "w26"])
        #expect(rows[1].covers == 25...26)
        #expect(rows[2].isContinuation)
        #expect(rows[2].words.isEmpty)
        #expect(rows[3].covers == nil)
    }

    // MARK: Text

    @Test func hebrewJoinsAsTheSourceWritesIt() throws {
        let words = try wordStudy().words(in: verse(1, 1, 4))
        let joined = OriginalText.joined(words.map(\.text))
        let expected = "וַיַּ֧רְא אֱלֹהִ֛ים אֶת־הָא֖וֹר כִּי־ט֑וֹב וַיַּבְדֵּ֣ל אֱלֹהִ֔ים בֵּ֥ין הָא֖וֹר וּבֵ֥ין הַחֹֽשֶׁךְ׃"
        let rightToLeft = words.allSatisfy { $0.language.isRightToLeft }
        #expect(joined == expected)
        #expect(rightToLeft)
        // Only spaces are added: every word is there, verbatim and in order.
        let letters = joined.replacingOccurrences(of: " ", with: "")
        let verbatim = words.map(\.text).joined()
        #expect(letters == verbatim)
    }

    @Test func paseqStandsApartAndMaqafJoins() throws {
        let words = try wordStudy().words(in: verse(1, 1, 5))
        let joined = OriginalText.joined(words.map(\.text))
        let shown = OriginalText.display("אֱלֹהִ֤ים׀")
        let plain = OriginalText.display("אֱלֹהִ֑ים")
        let maqaf = OriginalText.joined(["אֶת־", "הָא֖וֹר"])
        #expect(shown == "אֱלֹהִ֤ים ׀")
        #expect(plain == "אֱלֹהִ֑ים")
        #expect(maqaf == "אֶת־הָא֖וֹר")
        #expect(joined.hasPrefix("וַיִּקְרָ֨א אֱלֹהִ֤ים ׀ לָאוֹר֙"))
        #expect(joined.hasSuffix("י֥וֹם אֶחָֽד׃"))
    }

    @Test func greekKeepsItsPunctuation() throws {
        let words = try wordStudy().words(in: verse(43, 1, 1))
        let joined = OriginalText.joined(words.map(\.text))
        let leftToRight = words.allSatisfy { !$0.language.isRightToLeft }
        #expect(joined == "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος.")
        #expect(leftToRight)
    }

    // MARK: Greek editions

    /// One Greek edition's words of a verse (KJV numbering).
    private func greek(_ verse: VerseID, _ edition: GreekEdition) throws -> [OriginalWord] {
        try wordStudy().words(in: verse, greek: edition)
    }

    @Test func eachBibleReadsItsOwnGreek() {
        let kjv = Translation.kjv.greekSource
        let web = Translation.web.greekSource
        let asv = Translation.asv.greekSource
        let reinaValera = OriginalSource.greek(for: "RV1909")
        let unknown = OriginalSource.greek(for: "BSB")
        let unknownOffered = OriginalVersification.supports(Translation(id: "BSB", name: "", year: "", license: "", summary: ""))
        #expect(kjv == OriginalSource.Greek(edition: .textusReceptus, isExact: true))
        #expect(web == OriginalSource.Greek(edition: .byzantine, isExact: true))
        #expect(asv == OriginalSource.Greek(edition: .westcottHort, isExact: false))
        #expect(reinaValera == OriginalSource.Greek(edition: .textusReceptus, isExact: false))
        #expect(unknown == nil)
        #expect(!unknownOffered)
    }

    @Test func comparisonsCrossTheTwoFamilies() {
        let textusReceptus = GreekEdition.textusReceptus.comparison
        let byzantine = GreekEdition.byzantine.comparison
        let nestleAland = GreekEdition.nestleAland.comparison
        let westcottHort = GreekEdition.westcottHort.comparison
        #expect(textusReceptus == .nestleAland)
        #expect(byzantine == .nestleAland)
        #expect(nestleAland == .textusReceptus)
        #expect(westcottHort == .textusReceptus)
    }

    @Test func johannineCommaIsOnlyInTheTextusReceptus() throws {
        let textusReceptus = try greek(verse(62, 5, 7), .textusReceptus)
        let nestleAland = try greek(verse(62, 5, 7), .nestleAland)
        let byzantine = try greek(verse(62, 5, 7), .byzantine)
        let heaven = textusReceptus.contains { $0.text == "οὐρανῷ" }
        let marked = textusReceptus.filter(\.isNotInComparison).count
        let nestleAlandMarked = nestleAland.filter(\.isNotInComparison).count
        let shared = Array(textusReceptus.prefix(5).map(\.text))
        #expect(textusReceptus.count == 22)
        #expect(heaven)
        #expect(marked == 17, "In heaven, the Father, the Word … these three are one")
        #expect(nestleAland.count == 5)
        #expect(byzantine.count == 5)
        #expect(nestleAlandMarked == 0)
        #expect(shared == nestleAland.map(\.text))
    }

    @Test func actsEightThirtySevenIsOnlyInTheTextusReceptus() throws {
        let textusReceptus = try greek(verse(44, 8, 37), .textusReceptus)
        let nestleAland = try greek(verse(44, 8, 37), .nestleAland)
        let byzantine = try greek(verse(44, 8, 37), .byzantine)
        let allMarked = textusReceptus.allSatisfy(\.isNotInComparison)
        #expect(textusReceptus.count == 23)
        #expect(allMarked)
        #expect(nestleAland.isEmpty)
        #expect(byzantine.isEmpty)
    }

    @Test func romansSixteenTwentyFourIsInTheTraditionalTexts() throws {
        let textusReceptus = try greek(verse(45, 16, 24), .textusReceptus)
        let byzantine = try greek(verse(45, 16, 24), .byzantine)
        let nestleAland = try greek(verse(45, 16, 24), .nestleAland)
        let allMarked = textusReceptus.allSatisfy(\.isNotInComparison)
        #expect(textusReceptus.count == 11)
        #expect(byzantine.count == 11)
        #expect(allMarked)
        #expect(nestleAland.isEmpty)
    }

    @Test("Mark 16:9–20 and John 7:53–8:11 are in every edition", arguments: [GreekEdition.textusReceptus, .byzantine, .nestleAland])
    func longPassagesAreInEveryEdition(edition: GreekEdition) throws {
        let study = try wordStudy()
        let markEnding = (9...20).map { verse(41, 16, $0) }
        let adulteress = [verse(43, 7, 53)] + (1...11).map { verse(43, 8, $0) }
        let mark = try study.words(inVerses: markEnding, greek: edition)
        let john = try study.words(inVerses: adulteress, greek: edition)
        // Nestle-Aland prints both in double brackets; TAGNT keeps the words.
        #expect(mark.count == 12)
        #expect(john.count == 12)
    }

    @Test func johnSevenFiftyThreeFollowsEachEdition() throws {
        let textusReceptus = try greek(verse(43, 7, 53), .textusReceptus)
        let nestleAland = try greek(verse(43, 7, 53), .nestleAland)
        let traditional = textusReceptus.dropFirst().first?.text
        let critical = nestleAland.dropFirst().first?.text
        #expect(traditional == "ἐπορεύθη")
        #expect(critical == "ἐπορεύθησαν")
    }

    @Test func lukeTwoFourteenReadsEachEditionsWord() throws {
        let study = try wordStudy()
        let textusReceptus = try greek(verse(42, 2, 14), .textusReceptus)
        let byzantine = try greek(verse(42, 2, 14), .byzantine)
        let nestleAland = try greek(verse(42, 2, 14), .nestleAland)
        let last = try #require(textusReceptus.last)
        let instead = try study.reading(at: last, in: .nestleAland)
        #expect(last.text == "εὐδοκία.")
        #expect(byzantine.last?.text == "εὐδοκία.")
        #expect(nestleAland.last?.text == "εὐδοκίας.")
        #expect(last.isNotInComparison)
        #expect(instead == "εὐδοκίας.")
        #expect(textusReceptus.count == 11)
    }

    @Test func revelationTwentyTwoNineteenHasTheBookOrTheTree() throws {
        let textusReceptus = try greek(verse(66, 22, 19), .textusReceptus).map(\.text)
        let nestleAland = try greek(verse(66, 22, 19), .nestleAland).map(\.text)
        let byzantine = try greek(verse(66, 22, 19), .byzantine).map(\.text)
        let books = textusReceptus.filter { $0 == "βίβλου" }.count
        let treeInTextusReceptus = textusReceptus.contains("ξύλου")
        let treeInNestleAland = nestleAland.contains("ξύλου")
        let treeInByzantine = byzantine.contains("ξύλου")
        #expect(books == 2)
        #expect(!treeInTextusReceptus)
        #expect(treeInNestleAland)
        #expect(treeInByzantine)
    }

    @Test func lordsPrayerDoxologyIsInTheTraditionalTexts() throws {
        let textusReceptus = try greek(verse(40, 6, 13), .textusReceptus)
        let byzantine = try greek(verse(40, 6, 13), .byzantine)
        let nestleAland = try greek(verse(40, 6, 13), .nestleAland)
        let marked = textusReceptus.filter(\.isNotInComparison).count
        let byzantineMarked = byzantine.filter(\.isNotInComparison).count
        #expect(textusReceptus.count == 27)
        #expect(byzantine.count == 27)
        #expect(textusReceptus.last?.text == "ἀμήν.")
        #expect(nestleAland.count == 12)
        #expect(nestleAland.last?.text == "πονηροῦ")
        #expect(marked == 15)
        #expect(byzantineMarked == 15)
    }

    @Test func eachEditionKeepsItsOwnSpellingAndOrder() throws {
        // Matthew 1:1's sixth word, David.
        let textusReceptus = try greek(verse(40, 1, 1), .textusReceptus).map(\.text)
        let westcottHort = try greek(verse(40, 1, 1), .westcottHort).map(\.text)
        let nestleAland = try greek(verse(40, 1, 1), .nestleAland).map(\.text)
        let herodTR = try greek(verse(40, 2, 3), .textusReceptus).prefix(5).map(\.text)
        let herodNA = try greek(verse(40, 2, 3), .nestleAland).prefix(5).map(\.text)
        let spellingOnly = try greek(verse(40, 1, 1), .textusReceptus).filter(\.isNotInComparison)
        #expect(textusReceptus.count == 8)
        #expect(textusReceptus.dropFirst(5).first == "Δαβὶδ")
        #expect(westcottHort.dropFirst(5).first == "Δαυεὶδ")
        #expect(nestleAland.dropFirst(5).first == "Δαυὶδ")
        #expect(spellingOnly.isEmpty, "A spelling difference isn't a missing word")
        // "Herod the king" (TR) and "the king Herod" (NA): the same words, each in its order.
        #expect(herodTR == ["Ἀκούσας", "δὲ", "Ἡρῴδης", "ὁ", "βασιλεὺς"])
        #expect(herodNA == ["Ἀκούσας", "δὲ", "ὁ", "βασιλεὺς", "Ἡρῴδης"])
    }

    @Test func greekIsJoinedVerbatim() throws {
        let words = try greek(verse(42, 2, 14), .byzantine)
        let joined = OriginalText.joined(words.map(\.text))
        let letters = joined.replacingOccurrences(of: " ", with: "")
        let verbatim = words.map(\.text).joined()
        #expect(letters == verbatim)
        #expect(joined == "δόξα ἐν ὑψίστοις θεῷ, καὶ ἐπὶ γῆς εἰρήνη ἐν ἀνθρώποις εὐδοκία.")
    }

    @Test func hebrewIsNeverMarked() throws {
        let genesis = try wordStudy().words(in: verse(1, 1, 1), greek: .nestleAland)
        let unmarked = genesis.allSatisfy { !$0.isNotInComparison && $0.edition == nil }
        #expect(genesis.count == 7)
        #expect(unmarked)
    }

    // MARK: Grammar

    @Test func greekVerbsAreParsed() {
        let aorist = Morphology(code: "V-AAI-3S", language: .greek)
        #expect(aorist.partOfSpeech == .verb)
        #expect(aorist.tense == .aorist)
        #expect(aorist.voice == .active)
        #expect(aorist.mood == .indicative)
        #expect(aorist.person == 3)
        #expect(aorist.number == .singular)

        let participle = Morphology(code: "V-PAP-NSM", language: .greek)
        #expect(participle.tense == .present)
        #expect(participle.mood == .participle)
        #expect(participle.grammaticalCase == .nominative)
        #expect(participle.gender == .masculine)

        let perfect = Morphology(code: "V-2RAI-3S", language: .greek)
        #expect(perfect.tense == .perfect)
        let deponent = Morphology(code: "V-PNI-3S", language: .greek)
        #expect(deponent.voice == .middleOrPassiveDeponent)
    }

    @Test func greekNounsAndPronounsAreParsed() {
        let noun = Morphology(code: "N-GSF", language: .greek)
        #expect(noun.partOfSpeech == .noun)
        #expect(noun.grammaticalCase == .genitive)
        #expect(noun.number == .singular)
        #expect(noun.gender == .feminine)

        let pronoun = Morphology(code: "P-1GS", language: .greek)
        #expect(pronoun.partOfSpeech == .pronoun)
        #expect(pronoun.person == 1)
        #expect(pronoun.grammaticalCase == .genitive)

        let conjunction = Morphology(code: "CONJ", language: .greek)
        let details = conjunction.details.count
        #expect(conjunction.partOfSpeech == .conjunction)
        #expect(details == 1)
    }

    @Test func hebrewWordsAreParsed() {
        let wayyiqtol = Morphology(code: "Hc/Vqw3ms", language: .hebrew)
        #expect(wayyiqtol.partOfSpeech == .verb)
        #expect(wayyiqtol.stem == "Qal")
        #expect(wayyiqtol.verbForm == .sequentialImperfect)
        #expect(wayyiqtol.person == 3)
        #expect(wayyiqtol.gender == .masculine)
        #expect(wayyiqtol.number == .singular)
        #expect(wayyiqtol.prefixes == [.conjunction])

        let noun = Morphology(code: "HR/Ncmsc/Sp2ms", language: .hebrew)
        #expect(noun.partOfSpeech == .noun)
        #expect(noun.state == .construct)
        #expect(noun.prefixes == [.preposition])
        #expect(noun.suffix == Morphology.Suffix(person: 2, gender: .masculine, number: .singular))

        let article = Morphology(code: "HTd/Ncfsa", language: .hebrew)
        #expect(article.prefixes == [.article])
        #expect(article.gender == .feminine)
        #expect(article.state == .absolute)

        let aramaic = Morphology(code: "AVhp3ms", language: .hebrew)
        #expect(aramaic.isAramaic)
        #expect(aramaic.stem == "Haphel")

        let name = Morphology(code: "HNpm", language: .hebrew)
        let part = PartOfSpeech(morphology: "HC/Vqw3ms", language: .hebrew)
        #expect(name.partOfSpeech == .properNoun)
        #expect(part == .verb)
    }

    @Test func everyStoredCodeParses() throws {
        let words = try wordStudy().words(inVerses: (1...31).map { verse(1, 1, $0) })
        let all = words.values.flatMap { $0 }
        let parsed = all.filter { Morphology(code: $0.morphology, language: $0.language).partOfSpeech != nil }
        #expect(all.count > 400)
        #expect(parsed.count == all.count)
    }

    // MARK: Free preview

    @Test func freeAccountsSeeTheFirstVerses() throws {
        let rows = try rows(.kjv, ChapterID(book: 43, chapter: 1), limit: OriginalParallel.previewVerses)
        let shown = rows.filter { !$0.words.isEmpty }.map(\.number)
        let everyVerseText = rows.allSatisfy { !$0.text.isEmpty }
        #expect(OriginalParallel.previewVerses == 2)
        #expect(shown == [1, 2])
        // The Bible's own text is all there.
        #expect(rows.count == 51)
        #expect(everyVerseText)
    }

    private static func word(_ verse: VerseID, _ text: String) -> OriginalWord {
        OriginalWord(verse: verse, position: 1, text: text, transliteration: "", strongs: nil, gloss: "", morphology: "")
    }
}
