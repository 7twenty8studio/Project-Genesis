import Foundation
import SwiftData
import Testing
@testable import Genesis

/// Fill-in-the-blank handouts (owner's plan, 22 November 2026): the blank
/// rules (the same as web/src/lib/blanks.ts), reading them from
/// published_sermon, the member's saved work and syncing it, and the
/// handout's check, show and practice rules.
struct SermonBlanksTests {
    private let known: (Int) -> Bool = { [1, 2, 3].contains($0) }

    @Test func splitsTextAtItsBlanks() {
        let pieces = SermonBlanks.pieces("God is [[1]] and [[2]].", known: known)
        #expect(pieces == [.text("God is "), .blank(1), .text(" and "), .blank(2), .text(".")])
        #expect(SermonBlanks.numbers(in: "[[3]] then [[1]]", known: known) == [3, 1])
    }

    @Test func anUnknownMarkerStaysAsWords() {
        let pieces = SermonBlanks.pieces("See [[9]] and [[x]] and [[1]", known: known)
        #expect(pieces == [.text("See [[9]] and [[x]] and [[1]")])
    }

    @Test func copyShowsALineOrTheGivenWords() {
        #expect(SermonBlanks.filled("God is [[1]].", known: known) == "God is _____.")
        #expect(SermonBlanks.filled("God is [[1]].", known: known, fill: { _ in "Faithful" }) == "God is Faithful.")
    }

    @Test func caseAccentsSpacingAndPunctuationDontCount() {
        #expect(SermonBlanks.isCorrect("  faithful. ", answer: "Faithful"))
        #expect(SermonBlanks.isCorrect("Jesús", answer: "jesus"))
        #expect(SermonBlanks.isCorrect("the   Good  Shepherd", answer: "The Good Shepherd"))
        #expect(SermonBlanks.isCorrect("God\u{2019}s grace", answer: "God's grace"))
        #expect(!SermonBlanks.isCorrect("", answer: "Faithful"))
        #expect(!SermonBlanks.isCorrect("Faith", answer: "Faithful"))
    }

    @Test func copyTextFillsBlanksWithLines() {
        let blanks = [SermonBlank(n: 1, open: false, hint: nil, answer: nil)]
        let text = SermonOutline.copyText([
            .heading(id: "h", text: "We are [[1]]", level: 2),
            .list(id: "l", items: ["Come [[1]]"], ordered: false),
        ], blanks: blanks)
        #expect(text == "We are _____\n\n\u{2022} Come _____")
    }
}

struct SermonBlanksWireTests {
    private func sermon(_ extra: String) throws -> PublishedSermon? {
        let json = """
        {"status":"ok","id":"5b7a1c9e-0000-4000-8000-000000000001","slug":"abcde12345",
         "group_id":"00000000-0000-0000-0000-00000000c0de","church":"Grace","title":"Seeing God",
         "speaker":"Ana","series":null,"preached_on":"2026-11-15","location":"","language":"en",
         "audience":"link","blocks":[{"id":"p","kind":"paragraph","text":"God is [[1]] and [[2]]."}],
         "previous":null,"next":null,"is_member":false\(extra)}
        """
        let lookup = try ChurchSermonWire.lookup(from: Data(json.utf8))
        guard case let .sermon(sermon) = lookup else { return nil }
        return sermon
    }

    @Test func hiddenKeyComesWithoutAnswers() throws {
        let read = try sermon(#","revision":3,"answers":"hidden","blanks":[{"n":1,"open":false,"hint":"S"},{"n":2,"open":true,"hint":null}]"#)
        let sermon = try #require(read)
        #expect(sermon.revision == 3)
        #expect(sermon.answers == .hidden)
        #expect(sermon.hasBlanks)
        #expect(sermon.blanks == [SermonBlank(n: 1, open: false, hint: "S", answer: nil), SermonBlank(n: 2, open: true, hint: nil, answer: nil)])
    }

    @Test func revealedKeyComesWithAnswersButNeverForOpenBlanks() throws {
        let read = try sermon(#","revision":1,"answers":"revealed","blanks":[{"n":1,"open":false,"answer":"Seeing"},{"n":2,"open":true,"answer":"ignored"},{"n":0},{"n":"x"}]"#)
        let sermon = try #require(read)
        #expect(sermon.answers == .revealed)
        #expect(sermon.blanks.count == 2)
        #expect(sermon.blanks.first?.answer == "Seeing")
        #expect(sermon.blanks.last?.answer == nil)
    }

    @Test func aSermonFromBeforeHandoutsHasNoBlanks() throws {
        let read = try sermon("")
        let sermon = try #require(read)
        #expect(!sermon.hasBlanks)
        #expect(sermon.answers == .hidden)
        #expect(sermon.revision == 0)
    }
}

@MainActor
struct SermonHandoutSavingTests {
    private func published(revision: Int = 1, answers: SermonAnswers, answer: String? = "Seeing") -> PublishedSermon {
        var sermon = PublishedSermon(
            id: UUID(uuidString: "5B7A1C9E-0000-4000-8000-000000000001")!, slug: "abcde12345", groupID: UUID(), church: "Grace",
            title: "Seeing God", speaker: "Ana", series: nil, preachedOn: "2026-11-15", location: "", language: "en", cover: nil,
            audience: .link,
            blocks: [
                .paragraph(id: "p", text: "God is [[1]] and [[2]]."),
                .scripture(id: "s", reference: SermonReference(raw: "Mt 5:8", start: VerseID(rawValue: 40_005_008), end: nil, status: .verified, label: nil, translation: nil, quoteWithheld: false)),
            ],
            previous: nil, next: nil, isMember: false
        )
        sermon.revision = revision
        sermon.answers = answers
        sermon.blanks = [
            SermonBlank(n: 1, open: false, hint: nil, answer: answers == .revealed ? answer : nil),
            SermonBlank(n: 2, open: true, hint: nil, answer: nil),
        ]
        return sermon
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @Test func aSavedCopyKeepsTheOutlineAndOnlyARevealedKey() {
        let hidden = SermonHandout(sermon: published(answers: .hidden), responses: ["1": "seeing"], keepKey: false)
        #expect(!hidden.hasKey)
        #expect(hidden.outline == published(answers: .hidden).blocks)
        let revealed = SermonHandout(sermon: published(answers: .revealed), responses: [:], keepKey: true)
        #expect(revealed.hasKey)
    }

    @Test func savingKeepsAnEarlierKeyAndOtherRevisions() throws {
        let context = try context()
        ChurchSermonNotes.saveHandout(["1": "x"], for: published(answers: .revealed), in: context)
        // The church hides the key again: the member's saved key stays.
        let notes = ChurchSermonNotes.saveHandout(["1": "Seeing"], for: published(answers: .hidden), in: context)
        #expect(notes.handouts.count == 1)
        #expect(notes.handouts.first?.hasKey == true)
        #expect(notes.handouts.first?.responses == ["1": "Seeing"])
        // A new revision (the answer changed) starts its own saved copy, hidden.
        ChurchSermonNotes.saveHandout(["1": "Pure"], for: published(revision: 2, answers: .hidden), in: context)
        let saved = notes.handouts
        #expect(saved.count == 2)
        #expect(saved.last?.revision == 2)
        #expect(saved.last?.hasKey == false)
        #expect(saved.first?.blanks.first?.answer == "Seeing")
        let found = ChurchSermonNotes.savedHandout(for: published(revision: 2, answers: .hidden), in: context)
        #expect(found?.responses == ["1": "Pure"])
    }

    @Test func updatingSavedWorkLeavesItsKey() throws {
        let context = try context()
        let notes = ChurchSermonNotes.saveHandout(["1": "x"], for: published(answers: .revealed), in: context)
        let handout = try #require(notes.handouts.first)
        ChurchSermonNotes.update(handout, responses: ["1": "Seeing", "2": "Mine"], in: notes, context: context)
        #expect(notes.handouts.first?.responses == ["1": "Seeing", "2": "Mine"])
        #expect(notes.handouts.first?.hasKey == true)
    }

    @Test func keepsTheNewestTenThatFit() {
        let one = SermonHandout(sermon: published(answers: .hidden), responses: [:], keepKey: false)
        let many = (1...12).map { revision -> SermonHandout in
            var copy = one
            copy.revision = revision
            return copy
        }
        let kept = SermonHandout.decode(SermonHandout.encodeKept(many))
        #expect(kept.count == SermonHandout.maximumKept)
        #expect(kept.first?.revision == 3)
        var big = one
        big.responses = ["2": String(repeating: "a", count: 500_000)]
        let fit = SermonHandout.decode(SermonHandout.encodeKept([big, big, one]))
        #expect(fit.count == 2)
        #expect(SermonHandout.encode([]).isEmpty)
    }

    @Test func syncsOnlyWhenThereIsSavedWorkAndSurvivesTheRoundTrip() throws {
        let context = try context()
        let store = StudyStore(context: context)
        let plain = store.createSermon(church: "Grace")
        let user = UUID()
        let plainData = try SupabaseCoding.encoder().encode(RemoteSermon(plain, userID: user))
        let plainJSON = try JSONSerialization.jsonObject(with: plainData) as? [String: Any]
        let plainObject = try #require(plainJSON)
        #expect(!plainObject.keys.contains("handouts"))

        let notes = ChurchSermonNotes.saveHandout(["1": "Seeing", "2": "Mine"], for: published(answers: .revealed), in: context)
        let data = try SupabaseCoding.encoder().encode(RemoteSermon(notes, userID: user))
        let decoded = try SupabaseCoding.decoder().decode(RemoteSermon.self, from: data)
        let handout = try #require(decoded.handouts?.first)
        #expect(handout.sermonID == notes.sourceSermonID)
        #expect(handout.responses == ["1": "Seeing", "2": "Mine"])
        #expect(handout.hasKey)
        #expect(handout.outline.count == 2)
    }
}

/// What a handout saved, and how often.
@MainActor
private final class Saved {
    var last: [Int: String] = [:]
    var count = 0
}

@MainActor
struct HandoutModelTests {
    private let blanks = [
        SermonBlank(n: 1, open: false, hint: nil, answer: "Seeing"),
        SermonBlank(n: 2, open: true, hint: nil, answer: nil),
        SermonBlank(n: 3, open: false, hint: nil, answer: "Giver"),
    ]

    @Test func checkingWaitsForTheKey() {
        let hidden = blanks.map { SermonBlank(n: $0.n, open: $0.open, hint: nil, answer: nil) }
        let model = HandoutModel(blanks: hidden, answers: .hidden, responses: [1: "Seeing"]) { _ in }
        #expect(!model.canCheck)
        model.check()
        model.toggleShowing()
        #expect(model.grade(1) == nil)
        #expect(model.shownAnswer(1) == nil)
        // A key saved earlier for this revision still checks.
        let saved = HandoutModel(blanks: hidden, answers: .hidden, responses: [:], savedKey: blanks) { _ in }
        #expect(saved.canCheck)
    }

    @Test func checksAndShowsOnlyCheckableBlanks() {
        let saved = Saved()
        let model = HandoutModel(blanks: blanks, answers: .revealed, responses: [:]) { saved.last = $0; saved.count += 1 }
        model.set(1, "seeing")
        model.set(2, "My own words")
        model.set(3, "Taker")
        #expect(saved.last == [1: "seeing", 2: "My own words", 3: "Taker"])
        model.check()
        #expect(model.grade(1) == true)
        #expect(model.grade(2) == nil)
        #expect(model.grade(3) == false)
        #expect(model.score?.right == 1)
        #expect(model.score?.of == 2)
        model.toggleShowing()
        #expect(model.shownAnswer(3) == "Giver")
        #expect(model.shownAnswer(2) == nil)
        // Typing again clears the check.
        model.set(3, "Giver")
        #expect(model.grade(3) == nil)
    }

    @Test func practiceNeverTouchesTheSavedAnswers() {
        let saved = Saved()
        let model = HandoutModel(blanks: blanks, answers: .revealed, responses: [1: "Seeing"]) { saved.last = $0; saved.count += 1 }
        model.startPractice()
        #expect(model.isPracticing)
        #expect(model.value(1).isEmpty)
        model.set(1, "Something")
        #expect(saved.count == 0)
        model.endPractice()
        #expect(model.value(1) == "Seeing")
    }

    @Test func storedAnswersDropEmptyBoxes() {
        #expect(HandoutModel.stored([1: "a", 2: ""]) == ["1": "a"])
        #expect(HandoutModel.read(["1": "a", "x": "b"]) == [1: "a"])
    }
}
