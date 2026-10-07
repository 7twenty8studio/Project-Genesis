import Foundation

/// One line of a word's grammar, ready to show: "Tense: Aorist".
struct MorphologyDetail: Hashable, Identifiable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

extension Morphology {
    /// The grammar in plain words, in the order grammars give it.
    var details: [MorphologyDetail] {
        var rows: [MorphologyDetail] = []
        func add(_ label: String, _ value: String?) {
            if let value { rows.append(MorphologyDetail(label: label, value: value)) }
        }
        add(String(localized: "Part of speech"), partOfSpeech?.title)
        add(String(localized: "Stem"), stem)
        add(String(localized: "Form"), verbForm?.title)
        add(String(localized: "Tense"), tense?.title)
        add(String(localized: "Voice"), voice?.title)
        add(String(localized: "Mood"), mood?.title)
        add(String(localized: "Person"), person.flatMap(Self.personTitle))
        add(String(localized: "Case"), grammaticalCase?.title)
        add(String(localized: "Gender"), gender?.title)
        add(String(localized: "Number"), number?.title)
        add(String(localized: "State"), state?.title)
        if !prefixes.isEmpty {
            add(String(localized: "Joined to"), prefixes.map(\.title).formatted(.list(type: .and)))
        }
        if let suffix {
            let parts = [suffix.person.flatMap(Self.personTitle), suffix.gender?.title, suffix.number?.title].compactMap { $0 }
            add(String(localized: "Pronoun suffix"), parts.isEmpty ? nil : parts.formatted(.list(type: .and, width: .narrow)))
        }
        return rows
    }

    static func personTitle(_ person: Int) -> String? {
        switch person {
        case 1: String(localized: "First person")
        case 2: String(localized: "Second person")
        case 3: String(localized: "Third person")
        default: nil
        }
    }
}

extension Morphology.Gender {
    var title: String {
        switch self {
        case .masculine: String(localized: "Masculine")
        case .feminine: String(localized: "Feminine")
        case .neuter: String(localized: "Neuter")
        case .common: String(localized: "Common")
        }
    }
}

extension Morphology.Number {
    var title: String {
        switch self {
        case .singular: String(localized: "Singular")
        case .plural: String(localized: "Plural")
        case .dual: String(localized: "Dual")
        }
    }
}

extension Morphology.Case {
    var title: String {
        switch self {
        case .nominative: String(localized: "Nominative")
        case .genitive: String(localized: "Genitive")
        case .dative: String(localized: "Dative")
        case .accusative: String(localized: "Accusative")
        case .vocative: String(localized: "Vocative")
        }
    }
}

extension Morphology.State {
    var title: String {
        switch self {
        case .absolute: String(localized: "Absolute")
        case .construct: String(localized: "Construct")
        case .determined: String(localized: "Determined")
        }
    }
}

extension Morphology.Tense {
    var title: String {
        switch self {
        case .present: String(localized: "Present")
        case .imperfect: String(localized: "Imperfect")
        case .future: String(localized: "Future")
        case .aorist: String(localized: "Aorist")
        case .perfect: String(localized: "Perfect")
        case .pluperfect: String(localized: "Pluperfect")
        }
    }
}

extension Morphology.Voice {
    var title: String {
        switch self {
        case .active: String(localized: "Active")
        case .middle: String(localized: "Middle")
        case .passive: String(localized: "Passive")
        case .middleOrPassive: String(localized: "Middle or passive")
        case .middleDeponent: String(localized: "Middle (deponent)")
        case .passiveDeponent: String(localized: "Passive (deponent)")
        case .middleOrPassiveDeponent: String(localized: "Middle or passive (deponent)")
        }
    }
}

extension Morphology.Mood {
    var title: String {
        switch self {
        case .indicative: String(localized: "Indicative")
        case .subjunctive: String(localized: "Subjunctive")
        case .optative: String(localized: "Optative")
        case .imperative: String(localized: "Imperative")
        case .infinitive: String(localized: "Infinitive")
        case .participle: String(localized: "Participle")
        }
    }
}

extension Morphology.VerbForm {
    var title: String {
        switch self {
        case .perfect: String(localized: "Perfect")
        case .sequentialPerfect: String(localized: "Sequential perfect")
        case .imperfect: String(localized: "Imperfect")
        case .sequentialImperfect: String(localized: "Sequential imperfect")
        case .conjunctiveImperfect: String(localized: "Conjunctive imperfect")
        case .cohortative: String(localized: "Cohortative")
        case .jussive: String(localized: "Jussive")
        case .imperative: String(localized: "Imperative")
        case .activeParticiple: String(localized: "Active participle")
        case .passiveParticiple: String(localized: "Passive participle")
        case .infinitiveAbsolute: String(localized: "Infinitive absolute")
        case .infinitiveConstruct: String(localized: "Infinitive construct")
        }
    }
}

extension Morphology.Prefix {
    var title: String {
        switch self {
        case .conjunction: String(localized: "Conjunction")
        case .preposition: String(localized: "Preposition")
        case .article: String(localized: "Article")
        case .interrogative: String(localized: "Interrogative")
        }
    }
}
