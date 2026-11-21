import Foundation

extension BibleLibrary {
    /// The Bibles Memorize can be set to: every installed Bible but the
    /// YouVersion ones (their text never shows in a paid feature, our
    /// agreement with YouVersion, LICENSED_BIBLES.md › 5) and Premium Bibles
    /// without Premium.
    var memoriseBibles: [Translation] {
        Self.memoriseBibles(among: translations) { isLocked($0) }
    }

    nonisolated static func memoriseBibles(among translations: [Translation], isLocked: (Translation) -> Bool) -> [Translation] {
        translations.filter { !$0.isYouVersion && !isLocked($0) }
    }

    /// The Bible picked in Memorize's Bible menu, while it's still allowed
    /// (downloaded, and unlocked); nil means Automatic.
    var chosenMemoriseTranslation: Translation? {
        guard let id = memoriseTranslationID else { return nil }
        return memoriseBibles.first { $0.id == id }
    }

    /// The Bible new Memorize passages are added in: the one picked, else
    /// Automatic (the Bible being read, through `premiumToolsTranslation`).
    var memoriseTranslation: Translation { chosenMemoriseTranslation ?? premiumToolsTranslation }

    /// The Bible a Memorize passage is shown in (the list, the review, the
    /// games and the Memorize widget). The Bible picked in Memorize wins
    /// whenever it has the passage. On Automatic it's the Bible being read
    /// (through `premiumToolsTranslation`, never a YouVersion Bible), except
    /// that a passage keeps the Bible it was added in while that one is in
    /// the same language, so the words don't change between the KJV and the
    /// WEB. When the Bible being read doesn't have the passage, the saved one.
    func memoryTranslation(for verse: MemoryVerse) -> Translation {
        if let chosen = chosenMemoriseTranslation, (try? repository(for: chosen).verse(verse.start)) != nil {
            return chosen
        }
        let saved = memoriseBibles.first { $0.id == verse.translationID }
        let chosen = Self.memoryTranslation(saved: saved, reading: premiumToolsTranslation)
        if let saved, chosen != saved, (try? repository(for: chosen).verse(verse.start)) == nil {
            return saved
        }
        return chosen
    }

    /// Automatic's rule behind `memoryTranslation(for:)`, with both Bibles
    /// allowed in Memorize: the saved Bible while it's in the reader's
    /// language (the region aside), else the reader's.
    nonisolated static func memoryTranslation(saved: Translation?, reading: Translation) -> Translation {
        guard let saved, saved.baseLanguage == reading.baseLanguage else { return reading }
        return saved
    }
}
