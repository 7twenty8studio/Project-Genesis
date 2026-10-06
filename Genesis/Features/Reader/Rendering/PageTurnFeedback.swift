import AudioToolbox
import UIKit

/// The page-turn touches: a soft paper rustle and a tap, each with its own
/// level (Aa › Page-turn volume and strength).
///
/// The rustle is a real page turn, trimmed and softened by
/// Tools/Sounds/make_page_turn.py into five loudness levels
/// (Resources/Sounds/page-turn-1…5.caf). It plays as a system sound, so it
/// follows the silent switch and never touches the audio session narration
/// and ambient sounds share; system sounds can't set their own volume, so the
/// volume slider picks a level.
@MainActor
final class PageTurnFeedback {
    /// One for the app: the sounds are loaded once and kept.
    static let shared = PageTurnFeedback()

    nonisolated static let levels = 5

    private var soundIDs: [SystemSoundID] = []
    private var haptic: UIImpactFeedbackGenerator?
    private weak var hapticView: UIView?

    private init() {
        for level in 1...Self.levels {
            var id: SystemSoundID = 0
            if let url = Bundle.main.url(forResource: "page-turn-\(level)", withExtension: "caf") {
                AudioServicesCreateSystemSoundID(url as CFURL, &id)
            }
            soundIDs.append(id)
        }
    }

    /// The sound level (1…5) for a volume setting (0…1).
    nonisolated static func level(forVolume volume: Double) -> Int {
        let clamped = min(max(volume, 0), 1)
        return Int((clamped * Double(levels - 1)).rounded()) + 1
    }

    /// Readies the haptic engine so the first tap isn't late.
    func prepare(in view: UIView, haptic wantsHaptic: Bool) {
        guard wantsHaptic else {
            haptic = nil
            return
        }
        if haptic == nil || hapticView !== view {
            haptic = UIImpactFeedbackGenerator(style: .medium, view: view)
            hapticView = view
        }
        haptic?.prepare()
    }

    func pageTurned(sound: Bool, volume: Double, haptic wantsHaptic: Bool, strength: Double) {
        if sound { playSound(volume: volume) }
        if wantsHaptic {
            haptic?.impactOccurred(intensity: CGFloat(min(max(strength, 0.1), 1)))
            haptic?.prepare()
        }
    }

    /// Plays the rustle at a volume, e.g. while the slider is adjusted.
    func playSound(volume: Double) {
        let id = soundIDs[Self.level(forVolume: volume) - 1]
        if id != 0 { AudioServicesPlaySystemSound(id) }
    }
}
