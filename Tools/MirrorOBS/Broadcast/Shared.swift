import Foundation
import UIKit

/// What Mirror OBS and its broadcast extension share through their App Group:
/// the room (set in the app), this iPhone's name, whether it may broadcast
/// (the trial or the unlock, set by the app from StoreKit) and the extension's status.
/// The iPhone's ID comes from the vendor id iOS gives every app of one
/// developer, so it's the same in both without storing it.
enum Mirror {
    static let appGroup = "group.com.7twenty8studio.mirrorobs"
    static let broadcastExtension = "com.7twenty8studio.mirrorobs.broadcast"
    static let privacyPolicy = "https://www.7twenty8studio.com/services/obs-sharing/mirror/privacy"
    static let support = "https://www.7twenty8studio.com/services/obs-sharing/mirror"
    static let site = "https://www.7twenty8studio.com/services/obs-sharing"

    /// The public Supabase project OBS Sharing signals through (public values, the same the website uses).
    static let supabaseURL = "https://ulbpwygzwchsnvdeeife.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsYnB3eWd6d2Noc252ZGVlaWZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2MjY3MjAsImV4cCI6MjEwNjIwMjcyMH0.LieY3BPC1MHQZ8qzO06oulde048Pv5x9GsVVPYrUMUE"

    /// Shared with the extension; the app's own defaults if the App Group isn't there (unsigned builds).
    static var store: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Four letters and digits, the same in the app and its extension, kept until the app is deleted.
    static var deviceID: String {
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? "0000"
        let hex = vendor.replacingOccurrences(of: "-", with: "")
        return "iphone-" + String(hex.prefix(4)).uppercased()
    }

    /// A room code as the website accepts it: 3 to 40 letters, digits, dashes or underscores.
    static func cleanRoom(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...40).contains(code.count),
              code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" })
        else { return nil }
        return code
    }

    /// The room this iPhone joins: empty until the person types one, then remembered.
    static var room: String? {
        get { store.string(forKey: "room").flatMap(cleanRoom) }
        set { store.set(newValue.flatMap(cleanRoom), forKey: "room") }
    }

    /// The name the host page and the OBS dock show next to the ID.
    static var name: String {
        get {
            let saved = store.string(forKey: "name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "iPhone \(deviceID.suffix(4))" : String(saved.prefix(40))
        }
        set { store.set(newValue, forKey: "name") }
    }

    /// The OBS browser source for this iPhone (filling an iPhone-shaped source edge to edge).
    static func obsLink(room: String) -> String { "\(site)/obs?room=\(room)&device=\(deviceID)&fit=cover" }
    static func hostLink(room: String) -> String { "\(site)?room=\(room)" }
    static func dockLink(room: String) -> String { "\(site)/dock?room=\(room)" }

    // MARK: Access, written by the app whenever StoreKit answers

    /// Saved by the app: unlocked for good, or broadcasting allowed until the trial ends.
    static func saveAccess(unlocked: Bool, trialEnds: Date?) {
        store.set(unlocked, forKey: "unlocked")
        store.set(trialEnds?.timeIntervalSince1970, forKey: "trialEnds")
    }

    /// Whether a broadcast may start (read by the extension).
    static func canBroadcast(now: Date = Date()) -> Bool {
        if store.bool(forKey: "unlocked") { return true }
        let ends = store.double(forKey: "trialEnds")
        return ends > now.timeIntervalSince1970
    }

    // MARK: Status, written by the extension every 2 s while it broadcasts

    struct Status {
        var connected: Bool
        var viewers: Int
    }

    static func writeStatus(connected: Bool, viewers: Int) {
        store.set(["connected": connected, "viewers": viewers, "at": Date().timeIntervalSince1970], forKey: "status")
    }

    static func clearStatus() { store.removeObject(forKey: "status") }

    /// Nil when no broadcast has reported in the last 6 s.
    static func readStatus(now: Date = Date()) -> Status? {
        guard let s = store.dictionary(forKey: "status"), let at = s["at"] as? Double,
              now.timeIntervalSince1970 - at < 6 else { return nil }
        return Status(connected: s["connected"] as? Bool ?? false, viewers: s["viewers"] as? Int ?? 0)
    }
}
