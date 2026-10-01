import Foundation

/// Values injected at build time from Config/Secrets.xcconfig via Info.plist.
/// Each is nil when not configured, and the matching feature stays off.
struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let sentryDSN: String?
    /// Shown on the Premium screen. Defaults to Apple's standard licence agreement.
    let termsURL: URL
    /// Your privacy policy (required by App Review before release); the link is
    /// hidden until it's set.
    let privacyURL: URL?
    /// The AI study assistant (GENESIS_AI_ENABLED in Genesis.xcconfig). Off
    /// unless set to YES.
    let isAIEnabled: Bool

    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

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
        termsURL = value("GenesisTermsURL").flatMap(URL.init(string:)) ?? Self.appleStandardEULA
        privacyURL = value("GenesisPrivacyURL").flatMap(URL.init(string:))
        isAIEnabled = Self.isOn(value("GenesisAIEnabled"))
    }

    /// Reads an xcconfig switch: YES, true or 1 turn it on; anything else is off.
    static func isOn(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return ["yes", "true", "1"].contains(raw.lowercased())
    }
}
