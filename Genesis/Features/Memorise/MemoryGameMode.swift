import SwiftData
import SwiftUI

/// The Memorise games, chosen from the Memorise screen.
enum MemoryGameMode: String, CaseIterable, Identifiable, Sendable {
    case fillGaps, wordOrder, speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fillGaps: String(localized: "Fill the Gaps", comment: "Memorize game")
        case .wordOrder: String(localized: "Word Order", comment: "Memorize game")
        case .speed: String(localized: "Speed Round", comment: "Memorize game")
        }
    }

    var subtitle: String {
        switch self {
        case .fillGaps: String(localized: "Choose each missing word from the verse.", comment: "Memorize game: Fill the Gaps")
        case .wordOrder: String(localized: "Tap the verse's words back into order.", comment: "Memorize game: Word Order")
        case .speed: String(localized: "Recall as many verses as you can in one minute.", comment: "Memorize game: Speed Round")
        }
    }

    var symbol: String {
        switch self {
        case .fillGaps: "square.dashed"
        case .wordOrder: "arrow.left.arrow.right"
        case .speed: "timer"
        }
    }
}

/// A game over some passages, by id (opened as a full-screen cover).
/// `isPractice` when nothing was due and the person chose to play anyway.
struct MemoryGameSession: Identifiable, Hashable {
    let id = UUID()
    let mode: MemoryGameMode
    let cards: [UUID]
    let isPractice: Bool
}

/// Reads a passage's words for the games, verbatim from the Bible database.
@MainActor
struct MemoryPassageSource {
    let library: BibleLibrary
    let context: ModelContext

    func card(_ id: UUID) -> MemoryVerse? {
        let key = id
        var descriptor = FetchDescriptor<MemoryVerse>(predicate: #Predicate { $0.id == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func translation(for verse: MemoryVerse) -> Translation {
        library.translations.first { $0.id == verse.translationID } ?? library.currentTranslation
    }

    /// Each verse of the passage, as the database has it (one line each).
    func verseTexts(_ verse: MemoryVerse) -> [String] {
        let repository = library.repository(for: translation(for: verse))
        return ((try? repository.verses(from: verse.start, through: verse.end)) ?? []).map(\.plainText)
    }

    /// The whole passage, joined the same way as in the review.
    func passageText(_ verse: MemoryVerse) -> String {
        verseTexts(verse).joined(separator: " ")
    }

    /// The verses either side of the passage, only as a source of decoy words.
    func nearbyTexts(_ verse: MemoryVerse) -> [String] {
        let repository = library.repository(for: translation(for: verse))
        let before = (try? repository.verses(from: VerseID(rawValue: verse.startRaw - 2), through: VerseID(rawValue: verse.startRaw - 1))) ?? []
        let after = (try? repository.verses(from: VerseID(rawValue: verse.endRaw + 1), through: VerseID(rawValue: verse.endRaw + 2))) ?? []
        return (before + after).map(\.plainText)
    }
}
