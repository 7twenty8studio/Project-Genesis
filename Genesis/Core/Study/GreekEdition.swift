import Foundation

/// The printed Greek New Testaments WordStudy.sqlite holds, each rebuilt
/// word by word from STEPBible's TAGNT (Translators Amalgamated Greek NT),
/// which records which editions have every word, the different words some
/// have at the same place, their own spellings and their word order. The
/// raw values are the bits of `greek_words.editions` and `.found`
/// (Tools/StudyData/build_wordstudy.py).
enum GreekEdition: Int, CaseIterable, Hashable, Sendable {
    /// Nestle-Aland, 28th edition (2012): the modern critical text.
    case nestleAland = 1
    /// Westcott and Hort (1881): the first widely used critical text.
    case westcottHort = 2
    /// Scrivener's Textus Receptus (1894): the Greek behind the KJV.
    case textusReceptus = 4
    /// Robinson and Pierpont's Byzantine text (2005): the majority of manuscripts.
    case byzantine = 8

    /// The edition this one's words are checked against for the dotted
    /// marker: the other family of texts. The traditional texts (Textus
    /// Receptus, Byzantine) are compared with Nestle-Aland; the critical
    /// ones (Nestle-Aland, Westcott-Hort) with the Textus Receptus.
    var comparison: GreekEdition {
        switch self {
        case .textusReceptus, .byzantine: .nestleAland
        case .nestleAland, .westcottHort: .textusReceptus
        }
    }

    /// Its usual short name.
    var name: String {
        switch self {
        case .nestleAland: String(localized: "Nestle-Aland")
        case .westcottHort: String(localized: "Westcott–Hort")
        case .textusReceptus: String(localized: "Textus Receptus")
        case .byzantine: String(localized: "Byzantine text")
        }
    }

    /// Its name with editor and year.
    var fullName: String {
        switch self {
        case .nestleAland: String(localized: "Nestle-Aland, 28th edition (2012)")
        case .westcottHort: String(localized: "Westcott and Hort (1881)")
        case .textusReceptus: String(localized: "Textus Receptus (Scrivener, 1894)")
        case .byzantine: String(localized: "Byzantine text (Robinson and Pierpont, 2005)")
        }
    }

    /// One or two plain sentences about the edition.
    var about: String {
        switch self {
        case .nestleAland:
            String(localized: "The modern critical text, which gives most weight to the oldest manuscripts. Most modern Bibles are translated from it.")
        case .westcottHort:
            String(localized: "The first widely used critical text, built mainly on the oldest manuscripts. The English revisers of 1881 worked from a very similar Greek text.")
        case .textusReceptus:
            String(localized: "The Greek printed in the 1500s and 1600s; Scrivener's edition gives the readings the King James translators followed.")
        case .byzantine:
            String(localized: "The text found in the majority of Greek manuscripts, read by the Greek-speaking church for centuries.")
        }
    }

    /// What the spelling shown follows. TAGNT spells every word as
    /// Nestle-Aland does, and records another edition's own spelling only
    /// where it noted one.
    var spelling: String {
        switch self {
        case .nestleAland:
            String(localized: "Spelling follows Nestle-Aland's 28th edition.")
        case .westcottHort, .textusReceptus, .byzantine:
            String(localized: "Where STEPBible records this edition's own spelling, it's shown; otherwise spelling follows Nestle-Aland.")
        }
    }

    /// The marker line under the header: what the dotted words are.
    var dottedWords: String {
        switch self {
        case .nestleAland:
            String(localized: "Dotted words are in Nestle-Aland but not in the Textus Receptus, which leaves them out or reads differently.")
        case .westcottHort:
            String(localized: "Dotted words are in Westcott–Hort but not in the Textus Receptus, which leaves them out or reads differently.")
        case .textusReceptus:
            String(localized: "Dotted words are in the Textus Receptus but not in Nestle-Aland, which leaves them out or reads differently.")
        case .byzantine:
            String(localized: "Dotted words are in the Byzantine text but not in Nestle-Aland, which leaves them out or reads differently.")
        }
    }

    /// For a dotted word: this edition doesn't have it.
    var lacksWord: String {
        switch self {
        case .nestleAland: String(localized: "Nestle-Aland doesn't have this word.")
        case .westcottHort: String(localized: "Westcott–Hort doesn't have this word.")
        case .textusReceptus: String(localized: "The Textus Receptus doesn't have this word.")
        case .byzantine: String(localized: "The Byzantine text doesn't have this word.")
        }
    }

    /// For a dotted word: this edition has another word (`reading`) at the same place.
    func readsInstead(_ reading: String) -> String {
        switch self {
        case .nestleAland: String(localized: "Nestle-Aland has \(reading) here instead.")
        case .westcottHort: String(localized: "Westcott–Hort has \(reading) here instead.")
        case .textusReceptus: String(localized: "The Textus Receptus has \(reading) here instead.")
        case .byzantine: String(localized: "The Byzantine text has \(reading) here instead.")
        }
    }
}

/// A set of Greek editions (`GreekEdition` raw values as bits).
struct GreekEditions: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(_ edition: GreekEdition) {
        rawValue = edition.rawValue
    }

    func contains(_ edition: GreekEdition) -> Bool {
        contains(GreekEditions(edition))
    }
}

/// The Greek each Bible was translated from: one line per Bible. A Bible
/// listed here (and with its verse numbers lined up in
/// `OriginalVersification`) offers "Original (Hebrew & Greek)"; one that
/// isn't doesn't. Adding a licensed Bible means a line here and its
/// versification map.
enum OriginalSource {
    struct Greek: Hashable, Sendable {
        let edition: GreekEdition
        /// True when the Bible was translated from this very edition; false
        /// when it's the closest edition the app has.
        let isExact: Bool
    }

    static func greek(for translationID: String) -> Greek? {
        switch translationID {
        // Scrivener rebuilt the Greek the KJV translators followed.
        case "KJV": Greek(edition: .textusReceptus, isExact: true)
        // The Reina-Valera followed earlier printings of the Textus Receptus.
        case "RV1909": Greek(edition: .textusReceptus, isExact: false)
        // The WEB's New Testament is the Robinson-Pierpont Byzantine text.
        case "WEB": Greek(edition: .byzantine, isExact: true)
        // The ASV followed the English revisers' Greek of 1881, closest to Westcott-Hort.
        case "ASV": Greek(edition: .westcottHort, isExact: false)
        default: nil
        }
    }
}

extension Translation {
    /// The Greek this Bible was translated from (nil: no Original parallel).
    var greekSource: OriginalSource.Greek? {
        OriginalSource.greek(for: id)
    }
}
