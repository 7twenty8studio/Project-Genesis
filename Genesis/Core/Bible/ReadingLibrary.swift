import Foundation

/// One Bible on the Bibles screen: on this device, offered for download, or both.
struct LibraryEntry: Identifiable, Hashable, Sendable {
    let translation: Translation
    /// The catalog's offer; nil for a Bible only on this device.
    let download: DownloadableTranslation?
    let isInstalled: Bool
    let profile: TranslationProfile
    /// A recorded human narration exists (public.audio_recordings). Every
    /// Bible can also be read aloud by a device voice.
    let hasRecordedAudio: Bool

    var id: String { translation.id }
}

/// One language's Bibles on the Bibles screen.
struct LibrarySection: Identifiable, Hashable, Sendable {
    /// A base language: "pt" holds O Livro's "pt-PT" too.
    let language: String
    let entries: [LibraryEntry]

    var id: String { language }
}

/// Installed Bibles of one language, for the quick Bible menus.
struct TranslationGroup: Identifiable, Hashable, Sendable {
    /// A base language: "pt" holds O Livro's "pt-PT" too.
    let language: String
    let translations: [Translation]

    var id: String { language }
}

/// Home's Bibles on This Device: one language at a time, so the card stays
/// short however many Bibles people download.
struct BibleShelf: Equatable, Sendable {
    /// Every language with an installed Bible (the picker), current first.
    let groups: [TranslationGroup]
    /// The language shown.
    let language: String
    /// The Bibles listed: the one being read first, then the library's order.
    let shown: [Translation]
    /// Bibles of this language left for "Show all".
    let hiddenCount: Int

    /// The picker shows only when there's more than one language.
    var showsLanguages: Bool { groups.count > 1 }
}

/// What the guide suggests a Bible for.
enum ReadingPurpose: CaseIterable, Sendable {
    case study, everyday, classic

    var title: String {
        switch self {
        case .study: String(localized: "For close study")
        case .everyday: String(localized: "For everyday reading")
        case .classic: String(localized: "For reading aloud and memorizing")
        }
    }

    var systemImage: String {
        switch self {
        case .study: "magnifyingglass"
        case .everyday: "book"
        case .classic: "music.quarternote.3"
        }
    }
}

/// The Global Reading Library: Bibles grouped by language, the most read
/// first, with what helps people choose. Pure logic, so it's easy to test.
enum ReadingLibrary {
    /// The Bibles screen's "All Languages" choice.
    static let allLanguages = "all"

    /// Languages with at least one Bible, the preferred one first, then by
    /// name. Regions are grouped under their language: O Livro ("pt-PT")
    /// is listed under Português.
    static func languages(installed: [Translation], catalog: [DownloadableTranslation], preferred: String) -> [String] {
        let preferred = Translation.baseLanguage(of: preferred)
        let all = Set((installed.map(\.language) + catalog.map(\.language)).map(Translation.baseLanguage(of:)))
        return all.sorted { lhs, rhs in
            if (lhs == preferred) != (rhs == preferred) { return lhs == preferred }
            return AppLanguage.displayName(lhs) < AppLanguage.displayName(rhs)
        }
    }

    /// The language the Bibles screen opens on: the Bible being read's, else
    /// the app's (as at setup), else every language. It's the Bibles'
    /// language, never the app's screens'.
    static func defaultLanguage(current: Translation?, appLanguage: String, available: [String]) -> String {
        if let current, available.contains(current.baseLanguage) { return current.baseLanguage }
        let app = Translation.baseLanguage(of: appLanguage)
        return available.contains(app) ? app : allLanguages
    }

    /// Every installed Bible grouped by language for the reader's Bible menu
    /// and Home's Bibles on This Device: the current Bible's language first,
    /// then by name; each group keeps the library's order. Nothing is left
    /// out (the Bibles screen's menu is for browsing).
    static func groups(_ translations: [Translation], current: Translation) -> [TranslationGroup] {
        let languages = translations.map(\.baseLanguage).reduce(into: [String]()) { list, language in
            if !list.contains(language) { list.append(language) }
        }
        let first = current.baseLanguage
        return languages.sorted { lhs, rhs in
            if (lhs == first) != (rhs == first) { return lhs == first }
            return AppLanguage.displayName(lhs) < AppLanguage.displayName(rhs)
        }.map { language in
            TranslationGroup(language: language, translations: translations.filter { $0.baseLanguage == language })
        }
    }

    /// How many Bibles Home lists before "Show all".
    static let shelfLimit = 4

    /// Home's Bibles on This Device for a chosen language (nil, or one with
    /// no Bible left: the current Bible's). The current Bible leads its
    /// language; at most `limit` are listed unless `expanded`, and never
    /// hides just one (a "Show all" for a single Bible is no saving).
    static func shelf(
        _ translations: [Translation],
        current: Translation,
        language: String?,
        expanded: Bool,
        limit: Int = shelfLimit
    ) -> BibleShelf {
        let groups = groups(translations, current: current)
        let chosen = language.map(Translation.baseLanguage(of:))
        let group = groups.first { $0.language == chosen } ?? groups.first { $0.language == current.baseLanguage } ?? groups.first
        guard let group else {
            return BibleShelf(groups: [], language: current.baseLanguage, shown: [], hiddenCount: 0)
        }
        let ordered = group.translations.filter { $0 == current } + group.translations.filter { $0 != current }
        let fits = expanded || ordered.count <= limit + 1
        let shown = fits ? ordered : Array(ordered.prefix(limit))
        return BibleShelf(groups: groups, language: group.language, shown: shown, hiddenCount: ordered.count - shown.count)
    }

    /// The Bibles for a choice, one section per language: the chosen
    /// language alone, or every language (`allLanguages`) in `languages`' order.
    static func sections(
        for selection: String,
        installed: [Translation],
        catalog: [DownloadableTranslation],
        recordedTranslationIDs: Set<String>,
        preferred: String
    ) -> [LibrarySection] {
        let shown = selection == allLanguages
            ? languages(installed: installed, catalog: catalog, preferred: preferred)
            : [Translation.baseLanguage(of: selection)]
        return shown.compactMap { language in
            let list = entries(in: language, installed: installed, catalog: catalog, recordedTranslationIDs: recordedTranslationIDs)
            return list.isEmpty && selection == allLanguages ? nil : LibrarySection(language: language, entries: list)
        }
    }

    /// Every Bible in a language (and its regions: "pt" holds "pt-PT"): on
    /// this device or available, most read first (unknown popularity last,
    /// then by name).
    static func entries(
        in language: String,
        installed: [Translation],
        catalog: [DownloadableTranslation],
        recordedTranslationIDs: Set<String>
    ) -> [LibraryEntry] {
        let language = Translation.baseLanguage(of: language)
        var entries: [LibraryEntry] = installed.filter { $0.baseLanguage == language }.map { translation in
            let offer = catalog.first { $0.id == translation.id }
            return LibraryEntry(
                translation: translation,
                download: offer,
                isInstalled: true,
                profile: offer?.profile ?? profile(for: translation),
                hasRecordedAudio: recordedTranslationIDs.contains(translation.id)
            )
        }
        for item in catalog where Translation.baseLanguage(of: item.language) == language && !entries.contains(where: { $0.id == item.id }) {
            entries.append(LibraryEntry(
                translation: item.translation,
                download: item,
                isInstalled: false,
                profile: item.profile,
                hasRecordedAudio: recordedTranslationIDs.contains(item.id)
            ))
        }
        return entries.sorted { lhs, rhs in
            let left = lhs.profile.popularity ?? .max
            let right = rhs.profile.popularity ?? .max
            if left != right { return left < right }
            return lhs.translation.name < rhs.translation.name
        }
    }

    /// What the app knows about a Bible on this device without the catalog.
    static func profile(for translation: Translation) -> TranslationProfile {
        (TranslationProfile.builtIn[translation.id] ?? TranslationProfile())
            .filling(from: TranslationProfile(rights: TranslationProfile.rights(fromLicense: translation.license)))
    }

    /// The Bible the guide suggests for a purpose, or nil when nothing in the
    /// list fits it.
    static func suggestion(for purpose: ReadingPurpose, in entries: [LibraryEntry]) -> LibraryEntry? {
        // `entries` is already most-read first, so the first best score wins ties.
        let scored = entries.compactMap { entry -> (entry: LibraryEntry, score: Int)? in
            score(entry.profile, for: purpose).map { (entry: entry, score: $0) }
        }
        return scored.min { $0.score < $1.score }?.entry
    }

    /// Lower is better; nil means it doesn't suit the purpose.
    private static func score(_ profile: TranslationProfile, for purpose: ReadingPurpose) -> Int? {
        guard let approach = profile.approach, let level = profile.readingLevel else { return nil }
        switch purpose {
        case .study:
            // Close to the original, in wording that's easy to follow.
            guard approach == .wordForWord else { return nil }
            return [ReadingLevel.everyday, .formal, .traditional].firstIndex(of: level)
        case .everyday:
            guard level == .everyday else { return nil }
            return [TranslationApproach.balanced, .thoughtForThought, .wordForWord].firstIndex(of: approach)
        case .classic:
            return level == .traditional ? 0 : nil
        }
    }
}
