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

/// What the guide suggests a Bible for.
enum ReadingPurpose: CaseIterable, Sendable {
    case study, everyday, classic

    var title: String {
        switch self {
        case .study: String(localized: "For close study")
        case .everyday: String(localized: "For everyday reading")
        case .classic: String(localized: "For reading aloud and memorising")
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
    /// Languages with at least one Bible, the preferred one (the app's) first,
    /// then by name.
    static func languages(installed: [Translation], catalog: [DownloadableTranslation], preferred: String) -> [String] {
        let all = Set(installed.map(\.language) + catalog.map(\.language))
        return all.sorted { lhs, rhs in
            if (lhs == preferred) != (rhs == preferred) { return lhs == preferred }
            return AppLanguage.displayName(lhs) < AppLanguage.displayName(rhs)
        }
    }

    /// Every Bible in a language: on this device or available, most read
    /// first (unknown popularity last, then by name).
    static func entries(
        in language: String,
        installed: [Translation],
        catalog: [DownloadableTranslation],
        recordedTranslationIDs: Set<String>
    ) -> [LibraryEntry] {
        var entries: [LibraryEntry] = installed.filter { $0.language == language }.map { translation in
            let offer = catalog.first { $0.id == translation.id }
            return LibraryEntry(
                translation: translation,
                download: offer,
                isInstalled: true,
                profile: offer?.profile ?? profile(for: translation),
                hasRecordedAudio: recordedTranslationIDs.contains(translation.id)
            )
        }
        for item in catalog where item.language == language && !entries.contains(where: { $0.id == item.id }) {
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
