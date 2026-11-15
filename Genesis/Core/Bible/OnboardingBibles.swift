import Foundation

/// The Bibles offered when Versely first opens, and the one chosen for the
/// person before they pick.
///
/// The bundled Bibles are English, so someone whose iPhone (and so Versely)
/// is in Spanish would otherwise start in the KJV and see an English app
/// around the Scripture. Free Bibles in the app's language from the catalog
/// are offered too, first, and the first of them is chosen: picking one
/// downloads it (`BibleLibrary.download`) while setup carries on.
/// YouVersion Bibles take minutes to build, so they're left to the Bibles
/// screen. Offline (no catalog yet) only the bundled Bibles are offered.
enum OnboardingBibles {
    struct Option: Identifiable, Hashable, Sendable {
        let translation: Translation
        /// Set when it isn't on the device yet: chosen, it's downloaded.
        let download: DownloadableTranslation?

        var id: String { translation.id }
    }

    /// The Bibles on the device that can be read (`installed`, without
    /// locked Premium ones), plus free downloads in the app's language;
    /// those in the app's language first, the catalog's most read first
    /// among the downloads.
    static func options(
        installed: [Translation],
        catalog: [DownloadableTranslation],
        language: String
    ) -> [Option] {
        let onDevice = installed.map { Option(translation: $0, download: nil) }
        let downloads = catalog
            .filter { item in
                item.language == language && item.youVersionID == nil && !item.premium
                    && !installed.contains { $0.id == item.id }
            }
            .sorted { ($0.profile.popularity ?? .max) < ($1.profile.popularity ?? .max) }
            .map { Option(translation: $0.translation, download: $0) }
        let all = onDevice + downloads
        return all.filter { $0.translation.language == language } + all.filter { $0.translation.language != language }
    }

    /// The Bible chosen before the person picks: the current one if it's in
    /// the app's language, else the first offered in that language, else
    /// the current one.
    static func suggested(current: Translation, options: [Option], language: String) -> Translation {
        if current.language == language { return current }
        return options.first { $0.translation.language == language }?.translation ?? current
    }
}
