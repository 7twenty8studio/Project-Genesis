import Foundation

/// Which Bible a church sermon's passages open in. One choice for the whole
/// sermon (as on the guest page): picking a Bible on any passage opens every
/// passage of that sermon in it. Until then each opens in the person's own
/// Bible. Ids only; `ChurchPassageSheet` turns them into Bibles.
enum ChurchPassageBible {
    /// The Bibles a passage offers, each once: the person's Bible, the one
    /// they chose for this sermon, then the one the pastor quoted, keeping
    /// only those `isAvailable` (installed and not locked).
    static func options(current: String, chosen: String?, quoted: String?, isAvailable: (String) -> Bool) -> [String] {
        var list = [current]
        for id in [chosen, quoted].compactMap({ $0 }) where !list.contains(id) && isAvailable(id) {
            list.append(id)
        }
        return list
    }

    /// The Bible shown: the sermon's choice when it's offered, else the first.
    static func shown(options: [String], chosen: String?) -> String? {
        if let chosen, options.contains(chosen) { return chosen }
        return options.first
    }

    /// True when the pastor's label names the Bible shown ("kjv" and "KJV"
    /// alike), so the passage doesn't name it twice.
    static func labelNames(_ label: String?, id: String) -> Bool {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return false }
        return label.caseInsensitiveCompare(id) == .orderedSame
    }
}
