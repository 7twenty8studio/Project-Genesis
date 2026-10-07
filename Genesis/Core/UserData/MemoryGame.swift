import Foundation

// Memorise games (Premium). Everything here works on the passage's own words,
// exactly as the Bible database gives them: words are only hidden, shuffled or
// offered as choices, never invented, shortened or respelled. Joining the
// tokens back together reproduces the verse string character for character.

/// One word of a passage as it appears, with its punctuation attached.
struct VerseToken: Hashable, Sendable {
    /// The word as written, punctuation included ("heart;", "\u{201C}For").
    let text: String
    /// The whitespace that followed it in the passage ("" after the last word).
    let trailing: String

    /// True when the token holds a letter or digit (not just punctuation).
    var hasLetters: Bool { text.contains { $0.isLetter || $0.isNumber } }

    /// The word without the punctuation around it ("heart" for "heart;").
    /// Always a run of the verse's own characters.
    var core: String {
        guard let first = text.firstIndex(where: Self.isWordCharacter),
              let last = text.lastIndex(where: Self.isWordCharacter) else { return text }
        return String(text[first...last])
    }

    /// Punctuation before the word ("\u{201C}" for "\u{201C}For").
    var leadingPunctuation: String {
        guard let first = text.firstIndex(where: Self.isWordCharacter) else { return "" }
        return String(text[..<first])
    }

    /// Punctuation after the word (";" for "heart;").
    var trailingPunctuation: String {
        guard let last = text.lastIndex(where: Self.isWordCharacter) else { return "" }
        return String(text[text.index(after: last)...])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// A passage split into words, keeping every character so it can be rebuilt
/// exactly. Splits on whitespace only, so punctuation stays with its word;
/// a lone mark (an em dash between spaces) joins the word before it.
struct VerseWords: Equatable, Sendable {
    /// Whitespace before the first word (normally "").
    let leading: String
    let tokens: [VerseToken]

    init(_ text: String) {
        // Runs of non-whitespace, each with the whitespace after it.
        var leading = ""
        var pieces: [(text: String, trailing: String)] = []
        var word = ""
        var space = ""
        for character in text {
            if character.isWhitespace {
                if pieces.isEmpty && word.isEmpty { leading.append(character) } else { space.append(character) }
            } else {
                if !space.isEmpty {
                    pieces.append((word, space))
                    word = ""
                    space = ""
                }
                word.append(character)
            }
        }
        if !word.isEmpty { pieces.append((word, space)) }

        // Punctuation-only pieces join a neighbouring word so every chip is a word.
        var tokens: [VerseToken] = []
        var pendingPrefix = ""
        for piece in pieces {
            let isPunctuation = !piece.text.contains { $0.isLetter || $0.isNumber }
            if isPunctuation, let previous = tokens.last {
                tokens[tokens.count - 1] = VerseToken(text: previous.text + previous.trailing + piece.text, trailing: piece.trailing)
            } else if isPunctuation {
                pendingPrefix += piece.text + piece.trailing
            } else {
                tokens.append(VerseToken(text: pendingPrefix + piece.text, trailing: piece.trailing))
                pendingPrefix = ""
            }
        }
        if !pendingPrefix.isEmpty {
            // Nothing but punctuation: keep it as one token so nothing is lost.
            let body = pendingPrefix.trimmingTrailingWhitespace()
            tokens.append(VerseToken(text: body, trailing: String(pendingPrefix.dropFirst(body.count))))
        }
        self.leading = leading
        self.tokens = tokens
    }

    /// The passage rebuilt from its tokens: identical to the text it came from.
    var text: String { Self.join(leading: leading, tokens: tokens) }

    static func join(leading: String, tokens: some Sequence<VerseToken>) -> String {
        leading + tokens.map { $0.text + $0.trailing }.joined()
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
}

/// A small deterministic random source (SplitMix64), so a seed always gives
/// the same gaps, choices and shuffles in tests.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Rules shared by the games.
enum MemoryGame {
    /// The most gaps in one passage, so a long passage stays a short game.
    static let maximumGaps = 12
    /// Choices offered for each gap (the answer plus decoys), when the words allow.
    static let choiceCount = 4

    /// How many words to hide: more as the passage becomes better known.
    static func gapCount(wordCount: Int, mastery: MemoryMastery) -> Int {
        guard wordCount > 0 else { return 0 }
        let share: Double = switch mastery {
        case .new: 0.2
        case .learning: 0.35
        case .familiar: 0.5
        case .memorised: 0.7
        }
        let count = max(1, Int((Double(wordCount) * share).rounded()))
        return min(count, wordCount, maximumGaps)
    }

    /// Token positions to hide (ascending), chosen among real words only.
    static func gaps(in words: [VerseToken], count: Int, seed: UInt64) -> [Int] {
        let candidates = words.indices.filter { words[$0].hasLetters }
        guard count > 0, !candidates.isEmpty else { return [] }
        var generator = SeededGenerator(seed: seed)
        return Array(candidates.shuffled(using: &generator).prefix(count)).sorted()
    }

    /// Words to choose from for one gap: the answer and up to `count - 1`
    /// decoys, all taken verbatim from the passage (then from nearby verses
    /// in `extra` when the passage is short). No decoy matches the answer.
    static func choices(for answer: VerseToken, among words: [VerseToken], extra: [VerseToken] = [], count: Int = choiceCount, seed: UInt64) -> [String] {
        var generator = SeededGenerator(seed: seed)
        var seen: Set<String> = [key(answer.core)]
        func distinct(_ tokens: [VerseToken]) -> [String] {
            var result: [String] = []
            for token in tokens where token.hasLetters {
                if seen.insert(key(token.core)).inserted { result.append(token.core) }
            }
            return result
        }
        let own = distinct(words).shuffled(using: &generator)
        let nearby = distinct(extra).shuffled(using: &generator)
        let decoys = (own + nearby).prefix(max(0, count - 1))
        return (Array(decoys) + [answer.core]).shuffled(using: &generator)
    }

    /// True when a chosen word is the hidden one (ignoring case and accents,
    /// which never tell two choices apart since decoys can't share a key).
    static func matches(_ choice: String, _ answer: VerseToken) -> Bool {
        key(choice) == key(answer.core)
    }

    static func key(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// How a finished game maps onto the review schedule. A clean game counts
    /// as "Good", a slip or two as "Hard", many mistakes as "Again". Games
    /// never give "Easy": choosing among words or reordering them is
    /// recognition, a little easier than recalling the passage unaided, so
    /// it shouldn't push the next review as far out as a confident recall.
    static func grade(mistakes: Int, steps: Int) -> MemoryGrade {
        if mistakes <= 0 { return .good }
        if mistakes <= max(1, steps / 4) { return .hard }
        return .again
    }

    /// Speed Round is honest self-grading, like turning a review card:
    /// "I knew it" is a good review and "Not yet" brings it back soon.
    static func speedGrade(knewIt: Bool) -> MemoryGrade { knewIt ? .good : .again }

    /// A fresh seed for a game on screen (tests pass fixed seeds instead).
    static func randomSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }
}

/// Fill the Gaps: some words are hidden; the person picks each hidden word
/// in turn from a few of the passage's own words.
struct FillGapsGame: Equatable, Sendable {
    let words: VerseWords
    /// Hidden token positions, in reading order.
    let gaps: [Int]
    /// The choices for each gap, in the same order as `gaps`.
    let choiceSets: [[String]]
    private(set) var filled = 0
    private(set) var mistakes = 0

    /// - Parameter nearby: neighbouring verses' text, used only for decoys.
    init(text: String, mastery: MemoryMastery, nearby: [String] = [], seed: UInt64) {
        let words = VerseWords(text)
        let wordCount = words.tokens.filter(\.hasLetters).count
        let gaps = MemoryGame.gaps(in: words.tokens, count: MemoryGame.gapCount(wordCount: wordCount, mastery: mastery), seed: seed)
        let extra = nearby.flatMap { VerseWords($0).tokens }
        self.words = words
        self.gaps = gaps
        choiceSets = gaps.enumerated().map { offset, index in
            MemoryGame.choices(for: words.tokens[index], among: words.tokens, extra: extra, seed: seed &+ UInt64(offset + 1))
        }
    }

    var isSolved: Bool { filled >= gaps.count }

    /// The token waiting to be filled.
    var currentGap: Int? { isSolved ? nil : gaps[filled] }

    var currentChoices: [String] { isSolved ? [] : choiceSets[filled] }

    /// True for a word still hidden.
    func isHidden(_ index: Int) -> Bool { gaps[filled...].contains(index) }

    /// True for a word the person has filled in.
    func wasFilled(_ index: Int) -> Bool { gaps[..<filled].contains(index) }

    /// Tries a choice for the current gap; a wrong one counts a mistake and
    /// leaves the gap open.
    @discardableResult
    mutating func choose(_ choice: String) -> Bool {
        guard let index = currentGap else { return false }
        guard MemoryGame.matches(choice, words.tokens[index]) else {
            mistakes += 1
            return false
        }
        filled += 1
        return true
    }

    var grade: MemoryGrade { MemoryGame.grade(mistakes: mistakes, steps: gaps.count) }
}

/// Word Order: the passage's words as shuffled chips, tapped back in order.
struct WordOrderGame: Equatable, Sendable {
    let words: VerseWords
    /// Chip order on screen, as positions in `words.tokens`.
    let shuffled: [Int]
    /// Chips placed so far, in order.
    private(set) var placed: [Int] = []
    private(set) var mistakes = 0

    init(text: String, seed: UInt64) {
        words = VerseWords(text)
        var generator = SeededGenerator(seed: seed)
        var order = Array(words.tokens.indices).shuffled(using: &generator)
        // Never hand over the answer already in order.
        if order.count > 1, order == Array(words.tokens.indices) { order.swapAt(0, 1) }
        shuffled = order
    }

    var isSolved: Bool { placed.count >= words.tokens.count }

    func isPlaced(_ index: Int) -> Bool { placed.contains(index) }

    /// Tries a chip as the next word. Repeated words ("the", "and") are
    /// interchangeable: any chip with the same text fits. A wrong chip counts
    /// a mistake and doesn't advance.
    @discardableResult
    mutating func tap(_ index: Int) -> Bool {
        guard !isSolved, words.tokens.indices.contains(index), !isPlaced(index) else { return false }
        guard words.tokens[index].text == words.tokens[placed.count].text else {
            mistakes += 1
            return false
        }
        placed.append(index)
        return true
    }

    /// The passage so far. Built from the positions filled, so once solved it
    /// is exactly the verse text.
    var builtText: String {
        VerseWords.join(leading: words.leading, tokens: words.tokens.prefix(placed.count))
    }

    var grade: MemoryGrade { MemoryGame.grade(mistakes: mistakes, steps: words.tokens.count) }
}
