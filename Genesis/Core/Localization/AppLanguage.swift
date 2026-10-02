import Foundation

/// The language Genesis's screens are shown in: English or Spanish.
///
/// People choose it in the iPhone's Settings › Apps › Genesis › Language (iOS
/// offers this for every app with more than one language, and restarts the
/// app when it changes), or it follows the iPhone's own language. Genesis
/// doesn't keep its own copy of the choice.
enum AppLanguage {
    /// Languages the screens are translated into.
    static let supported = ["en", "es"]

    /// "en" or "es".
    static var code: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return supported.first { preferred.hasPrefix($0) } ?? "en"
    }

    static var isSpanish: Bool { code == "es" }

    /// The language's name in that language, e.g. "Español".
    static func displayName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
    }
}
