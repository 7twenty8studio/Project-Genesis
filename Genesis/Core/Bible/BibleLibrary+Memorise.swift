import Foundation

extension BibleLibrary {
    /// The Bible a Memorize passage is shown in (the list, the review, the
    /// games and the Memorize widget): the Bible being read now, through
    /// `premiumToolsTranslation` (never a YouVersion Bible). The Bible the
    /// passage was added in is kept only while it's in the same language,
    /// so the words being learned don't change when someone moves between
    /// the KJV and the WEB, but a passage added while reading in another
    /// language (the Bíblia Livre, say) follows the reader back to theirs.
    /// When the Bible being read doesn't have the passage, the saved one.
    func memoryTranslation(for verse: MemoryVerse) -> Translation {
        let saved = translations.first { $0.id == verse.translationID && !isLocked($0) }.map { premiumToolsTranslation(for: $0) }
        let chosen = Self.memoryTranslation(saved: saved, reading: premiumToolsTranslation)
        if let saved, chosen != saved, (try? repository(for: chosen).verse(verse.start)) == nil {
            return saved
        }
        return chosen
    }

    /// The rule behind `memoryTranslation(for:)`, with both Bibles already
    /// through `premiumToolsTranslation`: the saved Bible while it's in the
    /// reader's language (the region aside), else the reader's.
    nonisolated static func memoryTranslation(saved: Translation?, reading: Translation) -> Translation {
        guard let saved, saved.baseLanguage == reading.baseLanguage else { return reading }
        return saved
    }
}
