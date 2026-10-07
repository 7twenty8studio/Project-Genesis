import Foundation

/// Picks "From Your Reading": a verse from a chapter read in the last week
/// that reads well alone on a widget. No AI: a whole sentence of
/// comfortable length, the same all day.
enum ReadingVersePicker {
    static let lengths = 60...220

    /// A verse that starts a sentence and ends one, short enough for a widget.
    static func isComfortable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lengths.contains(trimmed.count) else { return false }
        // Opening quotes and Spanish ¿ ¡ come before the capital.
        let opening: Set<Character> = ["\u{201C}", "\u{2018}", "\"", "'", "\u{00BF}", "\u{00A1}", "("]
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")"]
        guard let first = trimmed.first(where: { !opening.contains($0) }), first.isLetter, first.isUppercase else { return false }
        guard let last = trimmed.last(where: { !closing.contains($0) }) else { return false }
        return [".", "!", "?"].contains(last)
    }

    /// The verse for a day (`VerseWidgetSchedule.dayNumber`): chapters take
    /// turns by day; within one, a comfortable verse chosen by the day.
    /// Nil when nothing read recently has one.
    static func pick(from chapters: [ChapterID], day: Int, verses: (ChapterID) -> [Verse]) -> Verse? {
        guard !chapters.isEmpty else { return nil }
        let start = ((day % chapters.count) + chapters.count) % chapters.count
        for step in 0..<chapters.count {
            let chapter = chapters[(start + step) % chapters.count]
            let candidates = verses(chapter).filter { isComfortable($0.plainText) }
            if !candidates.isEmpty {
                return candidates[WidgetVerses.mix(day) % candidates.count]
            }
        }
        return nil
    }
}

/// Builds the verse widget's passages for the snapshot, verbatim from the
/// Bible databases.
@MainActor
enum WidgetVerses {
    /// How many passages the free Random Verse rotates through (three days of
    /// three-hourly verses, so it keeps changing if the app isn't opened).
    nonisolated static let randomPoolSize = 24

    /// A fixed scramble of a number, so pools look random but are the same
    /// on every device and every run.
    nonisolated static func mix(_ value: Int) -> Int {
        var x = UInt64(bitPattern: Int64(value)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Int(x % UInt64(Int.max))
    }

    /// The encouraging passages, in a fixed mixed-up order (categories
    /// interleaved).
    nonisolated static let shuffled: [CategoryPassage] = VerseCategories.encouraging
        .sorted { (WidgetVerses.mix($0.start.rawValue), $0.start.rawValue) < (WidgetVerses.mix($1.start.rawValue), $1.start.rawValue) }

    /// The day's Random Verse pool: the next `count` of the shuffled list,
    /// moving on by `count` each day.
    nonisolated static func randomPool(on date: Date, count: Int = randomPoolSize, calendar: Calendar = .current) -> [CategoryPassage] {
        let all = shuffled
        guard !all.isEmpty else { return [] }
        let day = VerseWidgetSchedule.dayNumber(for: date, calendar: calendar)
        let start = (((day * count) % all.count) + all.count) % all.count
        return (0..<min(count, all.count)).map { all[(start + $0) % all.count] }
    }

    /// The Bible a passage is shown from: the person's when it numbers the
    /// passage like the KJV (or isn't one whose numbering is mapped),
    /// otherwise the KJV, so the reference never shows the wrong verse.
    nonisolated static func usesOwnBible(_ passage: CategoryPassage, translationID: String) -> Bool {
        guard let map = OriginalVersification.map(for: translationID) else { return true }
        return passage.verseIDs.allSatisfy { id in
            let alignment = map.alignment(of: id)
            return alignment.verses == [id] && alignment.kjv == [id]
        }
    }

    /// Passages with their text, from the current Bible where it has every
    /// verse, the KJV otherwise. Passages found in neither are left out.
    static func passages(_ items: [CategoryPassage], library: BibleLibrary) -> [WidgetSnapshot.Passage] {
        let current = library.currentTranslation
        let own = items.filter { usesOwnBible($0, translationID: current.id) }
        let ownText = (try? library.current.verses(withIDs: own.flatMap(\.verseIDs))) ?? [:]
        let kjvText = current.id == Translation.kjv.id ? ownText : ((try? library.repository(for: .kjv).verses(withIDs: items.flatMap(\.verseIDs))) ?? [:])
        return items.compactMap { item in
            if usesOwnBible(item, translationID: current.id), let found = makePassage(item, from: ownText, in: current) {
                return found
            }
            return makePassage(item, from: kjvText, in: .kjv)
        }
    }

    private static func makePassage(_ item: CategoryPassage, from verses: [VerseID: Verse], in translation: Translation) -> WidgetSnapshot.Passage? {
        let found = item.verseIDs.compactMap { verses[$0] }
        guard found.count == item.verseIDs.count else { return nil }
        return WidgetSnapshot.Passage(
            reference: item.reference.description(in: translation.language),
            text: found.map(\.plainText).joined(separator: " "),
            verse: item.start.rawValue,
            translation: translation.abbreviation
        )
    }

    /// Premium: every category's passages, by category.
    static func categories(library: BibleLibrary) -> [String: [WidgetSnapshot.Passage]] {
        var result: [String: [WidgetSnapshot.Passage]] = [:]
        for category in VerseCategory.allCases {
            result[category.rawValue] = passages(VerseCategories.passages(for: category), library: library)
        }
        return result
    }

    /// Premium: From Your Reading for each of the next `days` days, from the
    /// chapters read in the last week. Empty when nothing was read lately.
    static func fromReading(progress: ReadingProgress, library: BibleLibrary, now: Date, days: Int = 7, calendar: Calendar = .current) -> [String: WidgetSnapshot.Passage] {
        let chapters = progress.recentChapters(days: 7, endingOn: now)
        guard !chapters.isEmpty else { return [:] }
        let repository = library.current
        let translation = library.currentTranslation
        var cache: [ChapterID: [Verse]] = [:]
        var result: [String: WidgetSnapshot.Passage] = [:]
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let day = VerseWidgetSchedule.dayNumber(for: date, calendar: calendar)
            let verse = ReadingVersePicker.pick(from: chapters, day: day) { chapter in
                if let cached = cache[chapter] { return cached }
                let verses = (try? repository.chapter(chapter).verses) ?? []
                cache[chapter] = verses
                return verses
            }
            guard let verse else { continue }
            result[WidgetSnapshot.dayKey(for: date, calendar: calendar)] = WidgetSnapshot.Passage(
                reference: PassageReference(verse: verse.id).description(in: translation.language),
                text: verse.plainText,
                verse: verse.id.rawValue,
                translation: translation.abbreviation
            )
        }
        return result
    }
}
