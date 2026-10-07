import Foundation

/// The word under the finger when a verse was long-pressed, so the original
/// word lookup can start with it. `occurrence` counts earlier copies of the
/// same word in the verse (0 for the first).
struct PressedWord: Hashable, Sendable {
    let verse: VerseID
    let text: String
    let occurrence: Int
}

/// A Hebrew or Greek word that probably lies behind some selected English.
struct OriginalWordMatch: Identifiable, Hashable, Sendable {
    enum Basis: Hashable, Sendable {
        /// The selected English shares words with the word's gloss in this verse.
        case gloss
        /// Only the lexicon matched: its gloss, Strong's KJV renderings or
        /// (Hebrew) Strong's definition.
        case lexicon
    }

    let word: OriginalWord
    let basis: Basis
    /// Higher is better; only meaningful for ranking.
    let score: Double

    var id: Int { word.id }
    /// "Likely" when the gloss matched; otherwise only the closest match.
    var isLikely: Bool { basis == .gloss }
}

/// Finds the Hebrew or Greek words behind English words picked in a verse.
///
/// Approximate by design: WordStudy.sqlite gives each original word an
/// English gloss in context (STEPBible), which rarely matches a translation
/// word for word. Selected words and glosses are normalised (lower case,
/// accents and punctuation dropped, KJV endings and common irregular forms
/// reduced to a stem); function words are ignored unless they're all that was
/// picked. Glosses are tried first; terms no gloss explains are then looked
/// up in each word's lexicon entry. Works on English only.
enum OriginalWordMatcher {
    static let maximumMatches = 3

    /// The best few matches, best first (ties in the original word order),
    /// one per Strong's number. Empty when nothing matches.
    static func matches(
        for selection: String,
        in words: [OriginalWord],
        lexicon: [String: LexiconEntry],
        limit: Int = maximumMatches
    ) -> [OriginalWordMatch] {
        let selected = terms(in: selection)
        let content = selected.filter { !isFunctionWord($0) }
        let contentOnly = !content.isEmpty
        let wanted = Set((contentOnly ? content : selected).map(stem))
        guard !wanted.isEmpty, limit > 0 else { return [] }

        let glosses = words.map { stems(glossTerms($0.gloss), contentOnly: contentOnly) }
        var explained = Set<String>()
        for gloss in glosses {
            explained.formUnion(gloss.intersection(wanted))
        }
        let unexplained = wanted.subtracting(explained)

        var found: [OriginalWordMatch] = []
        for (word, gloss) in zip(words, glosses) {
            let shared = gloss.intersection(wanted)
            if !shared.isEmpty {
                let score = Double(shared.count) / Double(wanted.count) + 0.1 * Double(shared.count) / Double(gloss.count)
                found.append(OriginalWordMatch(word: word, basis: .gloss, score: score))
            } else if !unexplained.isEmpty, let strongs = word.strongs, let entry = lexicon[strongs],
                      let score = lexiconScore(entry, unexplained: unexplained, wanted: wanted.count, contentOnly: contentOnly) {
                found.append(OriginalWordMatch(word: word, basis: .lexicon, score: score))
            }
        }
        return best(found, limit: limit)
    }

    /// A lexicon match on terms no gloss in the verse explains: the entry's
    /// own gloss first, then Strong's KJV renderings, then (Hebrew only) its
    /// short definition. More specific entries rank higher.
    private static func lexiconScore(_ entry: LexiconEntry, unexplained: Set<String>, wanted: Int, contentOnly: Bool) -> Double? {
        let tiers: [(text: String, weight: Double)] = [(entry.gloss, 0.6), (expandingStrongsSuffixes(entry.usage), 0.5)]
        for tier in tiers {
            let renderings = stems(terms(in: tier.text), contentOnly: contentOnly)
            let hits = renderings.intersection(unexplained)
            if !hits.isEmpty {
                return tier.weight * Double(hits.count) / Double(wanted) + 0.05 * Double(hits.count) / Double(renderings.count)
            }
        }
        guard contentOnly, entry.language == .hebrew, !entry.definition.isEmpty else { return nil }
        let defined = stems(terms(in: entry.definition), contentOnly: true).intersection(unexplained)
        guard !defined.isEmpty else { return nil }
        return 0.25 * Double(defined.count) / Double(wanted)
    }

    /// Strong's shorthand spelled out: "bull(-ock)" -> "bull bullock",
    /// "who(-m, -se)" -> "who whom whose".
    static func expandingStrongsSuffixes(_ usage: String) -> String {
        usage.replacing(/([A-Za-z]+)\(([^)]*)\)/) { match -> String in
            let base = String(match.output.1)
            let forms = match.output.2.split(separator: ",").map { part -> String in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("-") ? base + trimmed.dropFirst() : trimmed
            }
            return ([base] + forms).joined(separator: " ")
        }
    }

    private static func best(_ found: [OriginalWordMatch], limit: Int) -> [OriginalWordMatch] {
        let ranked = found.sorted { first, second in
            first.score != second.score ? first.score > second.score : first.word.position < second.word.position
        }
        var seen = Set<String>()
        var result: [OriginalWordMatch] = []
        for match in ranked {
            let key = match.word.strongs ?? "#\(match.word.position)"
            guard seen.insert(key).inserted else { continue }
            result.append(match)
            if result.count == limit { break }
        }
        return result
    }

    private static func stems(_ terms: [String], contentOnly: Bool) -> Set<String> {
        Set((contentOnly ? terms.filter { !isFunctionWord($0) } : terms).map(stem))
    }

    // MARK: Normalising

    /// Lower-case words without accents or punctuation. Possessives lose their
    /// "'s", contractions become two words ("didn't" -> "did", "not"),
    /// pronouns take one form ("his", "him" -> "he") and a few older words take
    /// the glosses' modern ones ("everlasting" -> "eternal", "Jehovah" -> "yahweh").
    static func terms(in text: String) -> [String] {
        let folded = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
        var result: [String] = []
        for piece in folded.split(whereSeparator: { !($0.isLetter || $0 == "'") }) {
            var word = String(piece).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            if word.hasSuffix("'s") { word = String(word.dropLast(2)) }
            guard !word.isEmpty, word.allSatisfy({ $0.isASCII }) else { continue }
            if let split = contractions[word] {
                result.append(contentsOf: split)
            } else if word.hasSuffix("n't") {
                result.append(String(word.dropLast(3)))
                result.append("not")
            } else {
                result.append(pronouns[word] ?? synonyms[word] ?? word)
            }
        }
        return result
    }

    /// A gloss's terms, without the words STEPBible marks as supplied
    /// ("[is]") or untranslated ("<obj.>"). The divine name also answers to
    /// "Lord", as the KJV and others render it.
    static func glossTerms(_ gloss: String) -> [String] {
        let bare = gloss.replacingOccurrences(of: "<[^>]*>|\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        let found = terms(in: bare)
        return found.contains("yahweh") ? found + ["lord"] : found
    }

    /// A rough stem, the same for "love", "loved", "loveth" and "lovedst",
    /// or "beginning" and "begin". Not a dictionary: both sides of a
    /// comparison go through it, so it only has to be consistent.
    static func stem(_ term: String) -> String {
        var word = irregular[term] ?? term
        for (suffix, replacement) in suffixes where word.hasSuffix(suffix) {
            guard word.count - suffix.count >= 3 else { continue }
            if suffix == "s", word.hasSuffix("ss") { continue }
            if suffix == "ly", word.count < 6 || word.hasSuffix("ily") { continue }
            word = String(word.dropLast(suffix.count)) + replacement
            break
        }
        // "beginn" -> "begin" (but "spirit" and "glass" keep theirs).
        if word.count >= 4, let last = word.last, last == word.dropLast().last, !"lsz".contains(last) {
            word.removeLast()
        }
        if word.count >= 4, word.hasSuffix("e") {
            word.removeLast()
        }
        return word
    }

    static func isFunctionWord(_ term: String) -> Bool {
        functionWords.contains(term)
    }

    // MARK: Tables

    /// Longest first, so "lovedst" loses "edst" rather than "st".
    private static let suffixes: [(String, String)] = [
        ("edst", ""), ("eth", ""), ("est", ""), ("ies", "y"), ("ied", "y"),
        ("ing", ""), ("ed", ""), ("es", ""), ("ly", ""), ("s", ""),
    ]

    private static let functionWords: Set<String> = [
        "a", "an", "the", "of", "and", "to", "in", "into", "unto", "that", "for", "with", "by", "on", "at",
        "from", "as", "or", "but", "nor", "so", "then", "than", "this", "these", "those", "which", "who",
        "whom", "whose", "what", "when", "where", "there", "thereof", "therein", "therefore", "wherefore",
        "also", "even", "yet", "now", "all", "any", "some",
        "is", "are", "was", "were", "be", "been", "being", "am", "art", "wast", "wert", "it", "its",
        "he", "she", "they", "you", "we", "i",
        "shall", "shalt", "should", "shouldest", "will", "wilt", "would", "wouldest", "may", "mayest",
        "might", "can", "could", "couldest", "must", "let", "do", "did", "didst", "doth", "dost",
        "have", "has", "hath", "hast", "had",
    ]

    /// Every pronoun form maps to its subject form, so "his" finds "of him".
    private static let pronouns: [String: String] = {
        let forms: [String: [String]] = [
            "he": ["his", "him", "himself"],
            "she": ["her", "hers", "herself"],
            "they": ["their", "theirs", "them", "themselves"],
            "you": ["your", "yours", "ye", "thee", "thou", "thy", "thine", "yourself", "yourselves", "thyself"],
            "we": ["our", "ours", "us", "ourselves"],
            "i": ["my", "me", "mine", "myself"],
        ]
        var table: [String: String] = [:]
        for (subject, others) in forms {
            for other in others { table[other] = subject }
        }
        return table
    }()

    private static let contractions: [String: [String]] = [
        "cannot": ["can", "not"], "can't": ["can", "not"], "won't": ["will", "not"], "shan't": ["shall", "not"],
    ]

    /// Older words the glosses put in today's English, and the divine name
    /// as the glosses spell it.
    private static let synonyms: [String: String] = [
        "jehovah": "yahweh", "everlasting": "eternal", "whosoever": "everyone", "whoso": "everyone", "whoever": "everyone",
        "ghost": "spirit", "verily": "truly", "nigh": "near",
    ]

    /// Irregular forms, mostly the KJV's, mapped to a regular one.
    private static let irregular: [String: String] = [
        "gave": "give", "given": "give", "gavest": "give", "spake": "speak", "spoke": "speak", "spoken": "speak",
        "said": "say", "saith": "say", "came": "come", "wrought": "work", "brought": "bring", "sought": "seek",
        "taught": "teach", "thought": "think", "begat": "beget", "begotten": "beget", "slew": "slay",
        "slain": "slay", "sware": "swear", "sworn": "swear", "went": "go", "gone": "go", "goeth": "go",
        "doeth": "do", "made": "make", "took": "take", "taken": "take", "knew": "know", "known": "know",
        "saw": "see", "seen": "see", "heard": "hear", "ate": "eat", "eaten": "eat", "sat": "sit",
        "stood": "stand", "bare": "bear", "born": "bear", "borne": "bear", "fell": "fall", "fallen": "fall",
        "men": "man", "women": "woman", "children": "child", "feet": "foot", "brethren": "brother",
        "oxen": "ox", "became": "become", "began": "begin", "begun": "begin", "kept": "keep", "led": "lead",
        "left": "leave", "laid": "lay", "found": "find", "fled": "flee", "sent": "send", "dwelt": "dwell",
        "sold": "sell", "told": "tell", "rose": "rise", "risen": "rise", "arose": "arise", "chose": "choose",
        "chosen": "choose", "wrote": "write", "written": "write", "drank": "drink", "drunk": "drink",
        "got": "get", "gat": "get", "hid": "hide", "hidden": "hide", "smote": "smite", "smitten": "smite",
        "forgave": "forgive", "forgiven": "forgive", "understood": "understand", "overcame": "overcome",
        "broken": "break", "brake": "break", "broke": "break", "held": "hold", "burnt": "burn",
    ]
}

/// The words of a verse as ranges of its verbatim text, for picking words
/// to look up. Letters, with apostrophes and hyphens inside a word.
enum VerseWords {
    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var end = index
            while index < text.endIndex, text[index].isLetter || joiners.contains(text[index]) {
                if text[index].isLetter { end = text.index(after: index) }
                index = text.index(after: index)
            }
            result.append(start..<end)
        }
        return result
    }

    /// Which word to start with: the pressed word's copy in the verse, by
    /// occurrence (case-insensitive), if it's there.
    static func index(of pressed: PressedWord, in text: String, ranges: [Range<String.Index>]) -> Int? {
        let copies = ranges.indices.filter {
            text[ranges[$0]].caseInsensitiveCompare(pressed.text) == .orderedSame
        }
        guard !copies.isEmpty else { return nil }
        return copies[min(max(pressed.occurrence, 0), copies.count - 1)]
    }

    private static let joiners: Set<Character> = ["'", "\u{2019}", "-"]
}

/// A word's part of speech, read from its morphology code (ETCBC-style for
/// Hebrew and Aramaic, Robinson-style for Greek).
enum PartOfSpeech: Hashable, Sendable {
    case noun, properNoun, verb, adjective, adverb, pronoun, preposition, conjunction, article, particle, interjection

    init?(morphology: String, language: OriginalLanguage) {
        switch language {
        case .hebrew: self.init(hebrew: morphology)
        case .greek: self.init(greek: morphology)
        }
    }

    /// "HTd/Ncmsa" (H or A for the language, then prefixes / word / suffixes).
    private init?(hebrew code: String) {
        let parts = code.dropFirst().split(separator: "/")
        guard let main = parts.last(where: { !$0.hasPrefix("S") }), let head = main.first else { return nil }
        let detail = main.dropFirst().first
        switch head {
        case "V": self = .verb
        case "N": self = detail == "p" ? .properNoun : .noun
        case "A": self = .adjective
        case "R": self = .preposition
        case "C", "c": self = .conjunction
        case "D": self = .adverb
        case "P": self = .pronoun
        case "T": self = detail == "d" ? .article : .particle
        default: return nil
        }
    }

    /// "V-AAI-3S", "N-NSM", "CONJ".
    private init?(greek code: String) {
        let head = code.split(separator: "-").first.map(String.init) ?? code
        switch head {
        case "N": self = .noun
        case "V": self = .verb
        case "A": self = .adjective
        case "ADV": self = .adverb
        case "CONJ", "COND": self = .conjunction
        case "PREP": self = .preposition
        case "T": self = .article
        case "P", "F", "R", "D", "I", "X", "Q", "K", "C", "S": self = .pronoun
        case "PRT": self = .particle
        case "INJ": self = .interjection
        default: return nil
        }
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
