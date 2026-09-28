import Foundation

/// Values injected at build time from Config/Secrets.xcconfig via Info.plist.
/// Each is nil when not configured, and the matching feature stays off.
struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let sentryDSN: String?

    static let current = AppConfiguration(bundle: .main)

    init(bundle: Bundle) {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unset build setting arrives empty or as the literal "$(NAME)".
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        supabaseURL = value("GenesisSupabaseURL").flatMap(URL.init(string:))
        supabaseAnonKey = value("GenesisSupabaseAnonKey")
        sentryDSN = value("GenesisSentryDSN")
    }
}
