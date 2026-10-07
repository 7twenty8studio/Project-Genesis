import Foundation

/// A word's part of speech, read from its morphology code (ETCBC-style for
/// Hebrew and Aramaic, Robinson-style for Greek).
enum PartOfSpeech: Hashable, Sendable {
    case noun, properNoun, verb, adjective, adverb, pronoun, preposition, conjunction, article, particle, interjection

    init?(morphology: String, language: OriginalLanguage) {
        guard let part = Morphology(code: morphology, language: language).partOfSpeech else { return nil }
        self = part
    }

    var title: String {
        switch self {
        case .noun: String(localized: "Noun")
        case .properNoun: String(localized: "Proper noun")
        case .verb: String(localized: "Verb")
        case .adjective: String(localized: "Adjective")
        case .adverb: String(localized: "Adverb")
        case .pronoun: String(localized: "Pronoun")
        case .preposition: String(localized: "Preposition")
        case .conjunction: String(localized: "Conjunction")
        case .article: String(localized: "Article")
        case .particle: String(localized: "Particle")
        case .interjection: String(localized: "Interjection")
        }
    }
}

/// A morphology code in plain terms: part of speech and, as the code gives
/// them, tense, voice and mood (Greek verbs), stem and form (Hebrew verbs),
/// person, gender, number, case and state, and what's joined to a Hebrew
/// word (prefixed conjunction, preposition or article; pronoun suffix).
///
/// Greek (TAGNT, Robinson style): "V-AAI-3S", "V-PAP-NSM", "N-GSF", "CONJ",
/// "P-1GS", "S-1SNSM". Hebrew and Aramaic (TAHOT, OSHB style): a language
/// letter (H or A), then morphemes split by "/": "HC/Vqw3ms", "HR/Ncfsa",
/// "HNcmpc/Sp2ms".
struct Morphology: Hashable, Sendable {
    enum Gender: Hashable, Sendable { case masculine, feminine, neuter, common }
    enum Number: Hashable, Sendable { case singular, plural, dual }
    enum Case: Hashable, Sendable { case nominative, genitive, dative, accusative, vocative }
    enum State: Hashable, Sendable { case absolute, construct, determined }
    enum Tense: Hashable, Sendable { case present, imperfect, future, aorist, perfect, pluperfect }
    enum Voice: Hashable, Sendable {
        case active, middle, passive, middleOrPassive, middleDeponent, passiveDeponent, middleOrPassiveDeponent
    }
    enum Mood: Hashable, Sendable { case indicative, subjunctive, optative, imperative, infinitive, participle }
    /// Hebrew and Aramaic verb forms.
    enum VerbForm: Hashable, Sendable {
        case perfect, sequentialPerfect, imperfect, sequentialImperfect, conjunctiveImperfect
        case cohortative, jussive, imperative, activeParticiple, passiveParticiple
        case infinitiveAbsolute, infinitiveConstruct
    }
    /// What can be prefixed to a Hebrew word.
    enum Prefix: Hashable, Sendable { case conjunction, preposition, article, interrogative }
    /// A pronoun suffix on a Hebrew word ("his", "your").
    struct Suffix: Hashable, Sendable {
        let person: Int?
        let gender: Gender?
        let number: Number?
    }

    var partOfSpeech: PartOfSpeech?
    /// Hebrew or Aramaic verb stem (binyan), named as grammars do: Qal, Niphal…
    var stem: String?
    var verbForm: VerbForm?
    var tense: Tense?
    var voice: Voice?
    var mood: Mood?
    var person: Int?
    var gender: Gender?
    var number: Number?
    var grammaticalCase: Case?
    var state: State?
    var prefixes: [Prefix] = []
    var suffix: Suffix?
    var isAramaic = false

    init(code: String, language: OriginalLanguage) {
        switch language {
        case .greek: parseGreek(code)
        case .hebrew: parseHebrew(code)
        }
    }

    // MARK: Greek

    private mutating func parseGreek(_ code: String) {
        // Joined words ("CONJ + P-1NS"): the first describes the word.
        let main = code.components(separatedBy: " + ").first ?? code
        let parts = main.split(separator: "-").map(String.init)
        guard let head = parts.first else { return }
        switch head {
        case "V":
            partOfSpeech = .verb
            if parts.count > 1 { parseGreekVerb(parts[1]) }
            if parts.count > 2 { parsePersonOrCase(parts[2]) }
        case "N", "A", "T", "D", "R", "I", "X", "Q", "K", "C":
            partOfSpeech = Self.greekParts[head]
            if parts.count > 1 { parseCaseNumberGender(Substring(parts[1])) }
        case "P", "F":
            partOfSpeech = .pronoun
            if parts.count > 1 { parsePersonOrCase(parts[1]) }
        case "S":
            // Possessive: person, the possessor's number, then case, number, gender.
            partOfSpeech = .pronoun
            if parts.count > 1, let digit = parts[1].first?.wholeNumberValue {
                person = digit
                parseCaseNumberGender(parts[1].dropFirst(2))
            }
        default:
            partOfSpeech = Self.greekParts[head]
        }
    }

    private static let greekParts: [String: PartOfSpeech] = [
        "N": .noun, "A": .adjective, "T": .article, "D": .pronoun, "R": .pronoun, "I": .pronoun,
        "X": .pronoun, "Q": .pronoun, "K": .pronoun, "C": .pronoun,
        "ADV": .adverb, "CONJ": .conjunction, "COND": .conjunction, "PREP": .preposition,
        "PRT": .particle, "INJ": .interjection,
    ]

    /// "AAI", "2AAI", "PAP": tense, voice, mood (a leading 2 marks second
    /// aorist or perfect forms, the same tense).
    private mutating func parseGreekVerb(_ text: String) {
        let letters = Array(text.drop { $0.isNumber })
        guard letters.count >= 3 else { return }
        tense = Self.tenses[letters[0]]
        voice = Self.voices[letters[1]]
        mood = Self.moods[letters[2]]
    }

    private static let tenses: [Character: Tense] = [
        "P": .present, "I": .imperfect, "F": .future, "A": .aorist, "R": .perfect, "L": .pluperfect,
    ]
    private static let voices: [Character: Voice] = [
        "A": .active, "M": .middle, "P": .passive, "E": .middleOrPassive,
        "D": .middleDeponent, "O": .passiveDeponent, "N": .middleOrPassiveDeponent,
    ]
    private static let moods: [Character: Mood] = [
        "I": .indicative, "S": .subjunctive, "O": .optative, "M": .imperative,
        "N": .infinitive, "P": .participle, "R": .participle,
    ]
    private static let cases: [Character: Case] = [
        "N": .nominative, "G": .genitive, "D": .dative, "A": .accusative, "V": .vocative,
    ]
    private static let greekGenders: [Character: Gender] = ["M": .masculine, "F": .feminine, "N": .neuter]
    private static let greekNumbers: [Character: Number] = ["S": .singular, "P": .plural]
    private static let states: [Character: State] = ["a": .absolute, "c": .construct, "d": .determined]

    /// "3S" (person and number) or "NSM" (case, number, gender), or "1GS"
    /// (a personal pronoun: person, case, number).
    private mutating func parsePersonOrCase(_ text: String) {
        guard let first = text.first else { return }
        if let digit = first.wholeNumberValue {
            person = digit
            let rest = text.dropFirst()
            if rest.count == 1, let letter = rest.first {
                number = Self.greekNumbers[letter]
            } else {
                parseCaseNumberGender(rest)
            }
        } else {
            parseCaseNumberGender(Substring(text))
        }
    }

    private mutating func parseCaseNumberGender(_ text: Substring) {
        let letters = Array(text)
        guard let first = letters.first else { return }
        grammaticalCase = Self.cases[first]
        if letters.count > 1 { number = Self.greekNumbers[letters[1]] }
        if letters.count > 2 { gender = Self.greekGenders[letters[2]] }
    }

    // MARK: Hebrew and Aramaic

    private mutating func parseHebrew(_ code: String) {
        guard let language = code.first else { return }
        isAramaic = language == "A"
        let parts = code.dropFirst().split(separator: "/").map(String.init)
        guard let mainIndex = parts.lastIndex(where: { !$0.hasPrefix("S") }) else { return }
        prefixes = parts[..<mainIndex].compactMap(Self.prefixKind)
        if let suffixPart = parts[(mainIndex + 1)...].first(where: { $0.hasPrefix("Sp") }) {
            let letters = Array(suffixPart.dropFirst(2))
            suffix = Suffix(
                person: letters.first?.wholeNumberValue,
                gender: letters.count > 1 ? Self.hebrewGender(letters[1]) : nil,
                number: letters.count > 2 ? Self.hebrewNumber(letters[2]) : nil
            )
        }
        parseHebrewWord(Array(parts[mainIndex]))
    }

    private static func prefixKind(_ part: String) -> Prefix? {
        switch part {
        case "C", "c": .conjunction
        case "R", "Rd": .preposition
        case "Td": .article
        case "Ti": .interrogative
        default: nil
        }
    }

    private mutating func parseHebrewWord(_ letters: [Character]) {
        guard let head = letters.first else { return }
        let rest = Array(letters.dropFirst())
        switch head {
        case "V":
            partOfSpeech = .verb
            guard rest.count >= 2 else { return }
            stem = (isAramaic ? Self.aramaicStems : Self.hebrewStems)[rest[0]]
            verbForm = Self.verbForms[rest[1]]
            let tail = Array(rest.dropFirst(2))
            switch verbForm {
            case .activeParticiple, .passiveParticiple:
                parseGenderNumberState(tail)
            case .infinitiveAbsolute, .infinitiveConstruct, nil:
                break
            default:
                person = tail.first?.wholeNumberValue
                if tail.count > 1 { gender = Self.hebrewGender(tail[1]) }
                if tail.count > 2 { number = Self.hebrewNumber(tail[2]) }
            }
        case "N":
            partOfSpeech = rest.first == "p" ? .properNoun : .noun
            if rest.first != "p" { parseGenderNumberState(Array(rest.dropFirst())) }
        case "A":
            partOfSpeech = .adjective
            parseGenderNumberState(Array(rest.dropFirst()))
        case "P":
            partOfSpeech = .pronoun
            if rest.first == "p", rest.count >= 4 {
                person = rest[1].wholeNumberValue
                gender = Self.hebrewGender(rest[2])
                number = Self.hebrewNumber(rest[3])
            }
        case "R": partOfSpeech = .preposition
        case "C", "c": partOfSpeech = .conjunction
        case "D": partOfSpeech = .adverb
        case "T":
            switch rest.first {
            case "d": partOfSpeech = .article
            case "j": partOfSpeech = .interjection
            default: partOfSpeech = .particle
            }
        default: break
        }
    }

    private mutating func parseGenderNumberState(_ letters: [Character]) {
        if letters.count > 0 { gender = Self.hebrewGender(letters[0]) }
        if letters.count > 1 { number = Self.hebrewNumber(letters[1]) }
        if letters.count > 2 { state = Self.states[letters[2]] }
    }

    private static func hebrewGender(_ letter: Character) -> Gender? {
        switch letter {
        case "m": .masculine
        case "f": .feminine
        case "b", "c": .common
        default: nil
        }
    }

    private static func hebrewNumber(_ letter: Character) -> Number? {
        switch letter {
        case "s": .singular
        case "p": .plural
        case "d": .dual
        default: nil
        }
    }

    private static let verbForms: [Character: VerbForm] = [
        "p": .perfect, "q": .sequentialPerfect, "i": .imperfect, "w": .sequentialImperfect,
        "u": .conjunctiveImperfect, "h": .cohortative, "j": .jussive, "v": .imperative,
        "r": .activeParticiple, "s": .passiveParticiple, "a": .infinitiveAbsolute, "c": .infinitiveConstruct,
    ]

    /// Stem names are the grammars' own terms, the same in every language.
    private static let hebrewStems: [Character: String] = [
        "q": "Qal", "N": "Niphal", "p": "Piel", "P": "Pual", "h": "Hiphil", "H": "Hophal",
        "t": "Hithpael", "o": "Polel", "O": "Polal", "r": "Hithpolel", "m": "Poel", "M": "Poal",
        "k": "Palel", "K": "Pulal", "Q": "Qal passive", "l": "Pilpel", "L": "Polpal",
        "f": "Hithpalpel", "D": "Nithpael", "j": "Pealal", "i": "Pilel", "u": "Hothpaal",
        "c": "Tiphil", "v": "Hishtaphel", "w": "Nithpalel", "y": "Nithpoel", "z": "Hithpoel",
    ]

    private static let aramaicStems: [Character: String] = [
        "q": "Peal", "Q": "Peil", "u": "Hithpeel", "p": "Pael", "P": "Ithpaal", "M": "Hithpaal",
        "a": "Aphel", "h": "Haphel", "s": "Saphel", "e": "Shaphel", "H": "Hophal", "i": "Ithpeel",
        "t": "Hishtaphel", "v": "Ishtaphel", "w": "Hithaphel", "o": "Polel", "z": "Ithpoel",
        "r": "Hithpolel", "f": "Hithpalpel", "b": "Hephal", "c": "Tiphel", "m": "Poel",
        "l": "Palpel", "L": "Ithpalpel", "O": "Ithpolel", "G": "Ittaphal",
    ]
}
