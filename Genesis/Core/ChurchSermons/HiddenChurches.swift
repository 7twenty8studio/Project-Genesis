import Foundation
import Observation

/// Churches whose sermons the person chose not to see (the Block in
/// Report and Block, App Store guideline 1.2). Kept on this device; their
/// sermons leave search and the group page, and a link to one says it's
/// hidden, with a way to show it again. Nobody is told.
@MainActor
@Observable
final class HiddenChurches {
    private(set) var ids: Set<UUID>

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "churchSermons.hidden"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func isHidden(_ church: UUID) -> Bool {
        ids.contains(church)
    }

    func set(_ church: UUID, hidden: Bool) {
        if hidden { ids.insert(church) } else { ids.remove(church) }
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.key)
    }
}
