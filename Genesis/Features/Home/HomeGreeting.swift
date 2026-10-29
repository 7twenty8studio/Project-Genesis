import Foundation

/// The line at the top of Home: "Good morning, Jeovanni" by the hour, or
/// "Good morning" without a name.
enum HomeGreeting {
    static func text(hour: Int, name: String?) -> String {
        switch (hour, name) {
        case (4..<12, let name?): String(localized: "Good morning, \(name)")
        case (12..<17, let name?): String(localized: "Good afternoon, \(name)")
        case (_, let name?): String(localized: "Good evening, \(name)")
        case (4..<12, nil): String(localized: "Good morning")
        case (12..<17, nil): String(localized: "Good afternoon")
        case (_, nil): String(localized: "Good evening")
        }
    }
}
