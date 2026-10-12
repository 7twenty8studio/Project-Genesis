import Foundation

/// How a translation renders the original languages.
enum TranslationApproach: String, CaseIterable, Codable, Sendable {
    case wordForWord = "word_for_word"
    case balanced
    case thoughtForThought = "thought_for_thought"

    var title: String {
        switch self {
        case .wordForWord: String(localized: "Word for word")
        case .balanced: String(localized: "Balanced", comment: "Bible translation approach between word for word and thought for thought")
        case .thoughtForThought: String(localized: "Thought for thought")
        }
    }

    var detail: String {
        switch self {
        case .wordForWord: String(localized: "Follows the original wording and word order as closely as the language allows. Good for close study.")
        case .balanced: String(localized: "Stays close to the original wording but smooths it where a literal rendering would be hard to follow.")
        case .thoughtForThought: String(localized: "Puts each sentence's meaning into natural, everyday language. Easy to read at length.")
        }
    }

    var systemImage: String {
        switch self {
        case .wordForWord: "text.word.spacing"
        case .balanced: "scale.3d"
        case .thoughtForThought: "text.bubble"
        }
    }
}

/// How a translation reads.
enum ReadingLevel: String, CaseIterable, Codable, Sendable {
    case traditional
    case formal
    case everyday

    var title: String {
        switch self {
        case .traditional: String(localized: "Traditional language", comment: "Reading level of a Bible: older, classic wording")
        case .formal: String(localized: "Formal language", comment: "Reading level of a Bible")
        case .everyday: String(localized: "Everyday language", comment: "Reading level of a Bible: modern, conversational wording")
        }
    }

    var detail: String {
        switch self {
        case .traditional: String(localized: "Older wording such as \u{201C}thee\u{201D} and \u{201C}thou\u{201D}, much loved for reading aloud and memorizing.")
        case .formal: String(localized: "Modern but dignified language, close to the original's tone.")
        case .everyday: String(localized: "Modern, conversational language that reads like today's speech.")
        }
    }
}

/// Whether a translation is free to share or used under a licence.
enum TranslationRights: String, Codable, Sendable {
    case publicDomain = "public_domain"
    case licensed

    var title: String {
        switch self {
        case .publicDomain: String(localized: "Public domain")
        case .licensed: String(localized: "Licensed", comment: "A Bible translation used under a publisher's license")
        }
    }
}

/// What the Bibles screen tells people about a translation. Each part may be
/// unknown; the server's values win over what the app knows.
struct TranslationProfile: Hashable, Sendable {
    var approach: TranslationApproach?
    var readingLevel: ReadingLevel?
    var rights: TranslationRights?
    /// 1 = most read in its language.
    var popularity: Int?

    /// Fills each unknown part from `other`.
    func filling(from other: TranslationProfile?) -> TranslationProfile {
        guard let other else { return self }
        return TranslationProfile(
            approach: approach ?? other.approach,
            readingLevel: readingLevel ?? other.readingLevel,
            rights: rights ?? other.rights,
            popularity: popularity ?? other.popularity
        )
    }

    /// What the app knows without the server: the bundled Bibles and those
    /// offered for download today. Popularity is within each language.
    static let builtIn: [String: TranslationProfile] = [
        "KJV": TranslationProfile(approach: .wordForWord, readingLevel: .traditional, rights: .publicDomain, popularity: 1),
        "BSB": TranslationProfile(approach: .balanced, readingLevel: .everyday, rights: .publicDomain, popularity: 2),
        "WEB": TranslationProfile(approach: .wordForWord, readingLevel: .everyday, rights: .publicDomain, popularity: 3),
        "ASV": TranslationProfile(approach: .wordForWord, readingLevel: .traditional, rights: .publicDomain, popularity: 4),
        "RV1909": TranslationProfile(approach: .wordForWord, readingLevel: .traditional, rights: .publicDomain, popularity: 1),
    ]

    /// Reads the licence line when nothing else says: "Public domain" or
    /// "Dominio público".
    static func rights(fromLicense license: String) -> TranslationRights? {
        let text = license.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return text.contains("public domain") || text.contains("dominio publico") ? .publicDomain : nil
    }
}
