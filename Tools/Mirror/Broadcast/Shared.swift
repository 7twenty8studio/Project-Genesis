import Foundation
import UIKit

/// What the app and the broadcast extension agree on without sharing storage
/// (no App Group needed): the room, and this iPhone's ID, which both work out
/// the same way from the vendor id iOS gives every app of one developer.
enum Mirror {
    /// The show's room on /screen (the host page: /screen/host?room=Q2TKHV33JG).
    static let room = "Q2TKHV33JG"

    /// Versely's public Supabase project (the same public values the app and website use).
    static let supabaseURL = "https://ulbpwygzwchsnvdeeife.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsYnB3eWd6d2Noc252ZGVlaWZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2MjY3MjAsImV4cCI6MjEwNjIwMjcyMH0.LieY3BPC1MHQZ8qzO06oulde048Pv5x9GsVVPYrUMUE"

    /// Four letters and digits, the same in the app and its extension, kept until the app is deleted.
    static var deviceID: String {
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? "0000"
        let hex = vendor.replacingOccurrences(of: "-", with: "")
        return "iphone-" + String(hex.prefix(4)).uppercased()
    }

    /// The OBS browser source for this iPhone.
    static var obsLink: String {
        "https://versely.7twenty8studio.com/screen/obs?room=\(room)&device=\(deviceID)"
    }
}
