import Foundation

/// Which language the Original view's word meanings (glosses) are shown in.
/// It's chosen apart from the app's language: by default the meanings follow
/// the Bible being read (the Reina-Valera gets Spanish ones, the Bíblia Livre
/// Portuguese ones, the KJV English ones, whatever language the screens are
/// in), and the reader can pick another (`GlossLanguage.storageKey`, the
/// Word Meanings menu in the Original header).
enum GlossLanguageChoice: String, CaseIterable, Identifiable, Sendable {
    /// The language of the Bible being read, when there are glosses in it;
    /// English otherwise.
    case bible
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"

    var id: String { rawValue }
}

enum GlossLanguage {
    /// Where the reader's choice is kept (`GlossLanguageChoice.rawValue`).
    static let storageKey = "reader.original.glossLanguage"

    /// The language code the glosses are shown in: "en" (STEPBible's own
    /// English), "es" or "pt". `bibleLanguage` is the language of the Bible
    /// being read ("es", "pt", "pt-PT", "en", …); the app's language plays
    /// no part.
    static func code(for choice: GlossLanguageChoice, bibleLanguage: String) -> String {
        switch choice {
        case .bible:
            let base = Translation.baseLanguage(of: bibleLanguage)
            return OriginalGlosses.languages.contains(base) ? base : "en"
        case .english, .spanish, .portuguese:
            return choice.rawValue
        }
    }

    /// The reader's saved choice (Same as the Bible until they pick one).
    static func savedChoice(in defaults: UserDefaults = .standard) -> GlossLanguageChoice {
        defaults.string(forKey: storageKey).flatMap(GlossLanguageChoice.init(rawValue:)) ?? .bible
    }

    /// Whether glosses in `code` are translated ones, so the screens show
    /// `OriginalGlosses.translatedNote` and the credit: a translated
    /// language and the bundled Glosses.sqlite present.
    static func isTranslated(_ code: String) -> Bool {
        OriginalGlosses.languages.contains(code) && OriginalGlosses.bundled != nil
    }
}
