import Foundation

/// Features that can be switched on and off from Supabase without an app
/// update. Each is a row in public.feature_flags (key, enabled).
enum FeatureFlag: String, CaseIterable, Sendable {
    /// The AI study assistant: Explain, chapter study tools and the Study panel.
    case studyAssistant = "study_assistant"
    /// Church groups (on once the groups SQL has been run).
    case groups
    /// The public prayer wall and reflections.
    case community
}

/// Reads the server-side switches at launch and whenever the app comes to the
/// front. Everything is off until the server says otherwise; the last answer
/// is kept so an offline launch behaves like the previous one.
@MainActor
@Observable
final class FeatureFlagService {
    private(set) var values: [FeatureFlag: Bool]

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isOverridden: Bool
    private static let storageKey = "featureFlags"

    /// `override` fixes the values and skips the server (UI and unit tests).
    init(client: SupabaseClient?, defaults: UserDefaults = .standard, override: [FeatureFlag: Bool]? = nil) {
        self.client = client
        self.defaults = defaults
        isOverridden = override != nil
        if let override {
            values = override
        } else {
            let saved = defaults.dictionary(forKey: Self.storageKey) as? [String: Bool] ?? [:]
            values = Self.values(from: saved)
        }
    }

    func isOn(_ flag: FeatureFlag) -> Bool {
        values[flag] ?? false
    }

    /// Asks the server for the current switches. Keeps the last known values
    /// when offline or when Supabase isn't configured.
    func refresh() async {
        guard !isOverridden, let client else { return }
        guard let remote = try? await client.featureFlags() else { return }
        apply(remote)
    }

    /// Takes the server's rows; a missing row means off.
    func apply(_ remote: [String: Bool]) {
        guard !isOverridden else { return }
        let updated = Self.values(from: remote)
        if updated != values { values = updated }
        defaults.set(Dictionary(uniqueKeysWithValues: updated.map { ($0.key.rawValue, $0.value) }), forKey: Self.storageKey)
    }

    private static func values(from raw: [String: Bool]) -> [FeatureFlag: Bool] {
        Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, raw[$0.rawValue] ?? false) })
    }
}
