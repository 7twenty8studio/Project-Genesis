import Foundation

/// The language Versely's screens are shown in: English or Spanish.
///
/// People choose it in Versely's Settings › Language (`AppLanguageChoice`) or
/// in the iPhone's Settings › Apps › Versely › Language; both write the same
/// AppleLanguages value in the app's own defaults. Without a choice it
/// follows the iPhone's own language.
enum AppLanguage {
    /// Languages the screens are translated into.
    static let supported = ["en", "es"]

    /// "en" or "es". Fixed for the life of the process: a choice made in
    /// Versely applies the next time it opens (iOS restarts the app when it's
    /// changed in the Settings app).
    static let code: String = {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return supported.first { preferred.hasPrefix($0) } ?? "en"
    }()

    static var isSpanish: Bool { code == "es" }

    /// The language's name in that language, e.g. "Español".
    static func displayName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
    }
}

/// Settings › Language: follow the iPhone, or always English or Spanish.
///
/// The choice is the app's own AppleLanguages value, the same one the
/// Settings app writes, so either place shows the other's choice. Bundles
/// read it at launch, so the screens change the next time Versely opens.
/// Widgets run in their own process and keep the iPhone's language.
enum AppLanguageChoice: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    /// The language code it fixes, nil when following the iPhone.
    var code: String? { self == .system ? nil : rawValue }

    /// "English" and "Español" in their own language, so anyone can find theirs.
    var title: String {
        guard let code else { return String(localized: "Same as iPhone") }
        return AppLanguage.displayName(code)
    }

    /// The choice that the app's saved AppleLanguages list means: its first
    /// language if Versely has a translation for it, otherwise the iPhone's.
    init(appleLanguages: [String]?) {
        let first = appleLanguages?.first ?? ""
        self = AppLanguageChoice.allCases.first { choice in
            guard let code = choice.code else { return false }
            return first.hasPrefix(code)
        } ?? .system
    }

    private static let key = "AppleLanguages"

    /// Read from the app's own defaults only (`standard` would also return
    /// the iPhone's list, which isn't a choice).
    static var saved: AppLanguageChoice {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
            return AppLanguageChoice(appleLanguages: domain?[key] as? [String])
        }
        set {
            if let code = newValue.code {
                UserDefaults.standard.set([code], forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// The choice Versely opened with, which the screens show.
    static let atLaunch = saved
}
