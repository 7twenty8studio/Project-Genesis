import UIKit

/// Where system sign-in sheets (Apple, Google) appear.
@MainActor
enum PresentationWindow {
    /// The key window of the active scene (or any window), so the sheet has
    /// somewhere to appear; nil only if the app has no window at all.
    static func current() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.keyWindow ?? scene?.windows.first { return window }
        if let scene { return UIWindow(windowScene: scene) }
        return nil
    }
}
