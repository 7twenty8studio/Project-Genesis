import AudioToolbox
import UIKit

/// The page-turn touches: a soft paper rustle and a light tap.
///
/// The rustle (Resources/Sounds/page-turn.caf, made by
/// Tools/Sounds/make_page_turn.py) plays as a system sound, so it follows the
/// silent switch and never touches the audio session that narration and
/// ambient sounds share.
@MainActor
final class PageTurnFeedback {
    /// One for the app: the sound is loaded once and kept.
    static let shared = PageTurnFeedback()

    private var soundID: SystemSoundID = 0
    private var haptic: UIImpactFeedbackGenerator?
    private weak var hapticView: UIView?

    private init() {
        if let url = Bundle.main.url(forResource: "page-turn", withExtension: "caf") {
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
    }

    /// Readies the haptic engine so the first tap isn't late.
    func prepare(in view: UIView, haptic wantsHaptic: Bool) {
        guard wantsHaptic else {
            haptic = nil
            return
        }
        if haptic == nil || hapticView !== view {
            haptic = UIImpactFeedbackGenerator(style: .soft, view: view)
            hapticView = view
        }
        haptic?.prepare()
    }

    func pageTurned(sound: Bool, haptic wantsHaptic: Bool) {
        if sound, soundID != 0 { AudioServicesPlaySystemSound(soundID) }
        if wantsHaptic {
            haptic?.impactOccurred(intensity: 0.55)
            haptic?.prepare()
        }
    }
}
