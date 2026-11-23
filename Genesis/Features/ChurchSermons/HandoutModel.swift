import Foundation
import Observation

/// A fill-in-the-blank handout being filled in (owner's plan, 22 November
/// 2026): the member's answers, a practice try, and the key when there is
/// one. Check Answers and Show Answers come together, only with the key
/// revealed for this revision (from the church now, or saved with the
/// member's work once it was). Practice Again starts a fresh try and never
/// touches the saved answers.
@MainActor
@Observable
final class HandoutModel {
    /// Each blank by number, in order.
    let blanks: [SermonBlank]
    /// What the church says about the key now (or, for saved work, whether it was kept).
    let answers: SermonAnswers
    private(set) var key: [Int: String]
    private(set) var responses: [Int: String]
    /// A fresh try's words, or nil when filling in the saved answers.
    private(set) var practice: [Int: String]?
    private(set) var checked = false
    private(set) var showing = false
    @ObservationIgnored private let save: @MainActor ([Int: String]) -> Void

    init(blanks: [SermonBlank], answers: SermonAnswers, responses: [Int: String], savedKey: [SermonBlank] = [], save: @escaping @MainActor ([Int: String]) -> Void) {
        self.blanks = blanks.sorted { $0.n < $1.n }
        self.answers = answers
        self.responses = responses
        self.save = save
        var key: [Int: String] = [:]
        for blank in savedKey where blank.isCheckable { key[blank.n] = blank.answer }
        if answers == .revealed {
            for blank in blanks where blank.isCheckable { key[blank.n] = blank.answer }
        }
        self.key = key
    }

    var known: Set<Int> { Set(blanks.map(\.n)) }
    func blank(_ n: Int) -> SermonBlank? { blanks.first { $0.n == n } }

    /// Check Answers and Show Answers: only with the key for this revision.
    var canCheck: Bool { !key.isEmpty }
    var isPracticing: Bool { practice != nil }

    func value(_ n: Int) -> String { (practice ?? responses)[n] ?? "" }

    func set(_ n: Int, _ text: String) {
        checked = false
        if practice != nil {
            practice?[n] = text
            return
        }
        responses[n] = text
        save(responses)
    }

    /// Right or not yet, once checked; nil for an open blank or before checking.
    func grade(_ n: Int) -> Bool? {
        guard checked, let answer = key[n] else { return nil }
        return SermonBlanks.isCorrect(value(n), answer: answer)
    }

    /// The key's word for a blank, while Show Answers is on.
    func shownAnswer(_ n: Int) -> String? { showing ? key[n] : nil }

    func check() {
        guard canCheck else { return }
        checked = true
    }

    func toggleShowing() {
        guard canCheck else { return }
        showing.toggle()
    }

    func startPractice() {
        practice = [:]
        checked = false
        showing = false
    }

    func endPractice() {
        practice = nil
        checked = false
    }

    /// How many checkable blanks are right, once checked.
    var score: (right: Int, of: Int)? {
        guard checked else { return nil }
        let graded = blanks.compactMap { grade($0.n) }
        return (graded.filter { $0 }.count, graded.count)
    }

    /// The line under the handout.
    var status: String {
        if isPracticing { return String(localized: "Practicing: a fresh try. Your saved answers are kept.") }
        if let score {
            let rightCount = score.right
            let total = score.of
            return String(localized: "\(rightCount) of \(total) right.")
        }
        if canCheck { return String(localized: "The answers are ready. Your answers are saved privately with your notes.") }
        if answers == .never { return String(localized: "Fill in the blanks as you listen. Your answers are saved privately with your notes.") }
        return String(localized: "Fill in the blanks as you listen. Your answers are saved privately with your notes, and you can check them once the church shares the answers.")
    }

    /// Saved answers keyed by number as text, for `SermonHandout`.
    static func stored(_ responses: [Int: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: responses.filter { !$0.value.isEmpty }.map { (String($0.key), $0.value) })
    }

    static func read(_ responses: [String: String]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: responses.compactMap { key, value in Int(key).map { ($0, value) } })
    }
}
