import ReplayKit
import SwiftUI

/// iOS only starts a screen broadcast from its own picker button, which is
/// small and hard to see. We keep that picker hidden behind our big button
/// and press it for the person, so the system sheet opens on our extension.
final class BroadcastLauncher {
    let picker: RPSystemBroadcastPickerView = {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = Mirror.broadcastExtension
        picker.showsMicrophoneButton = false
        return picker
    }()

    /// Opens the system's Start / Stop Broadcast sheet.
    func open() {
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
        }
    }
}

/// Puts the hidden picker in the window (it only works from there).
struct HiddenPicker: UIViewRepresentable {
    let launcher: BroadcastLauncher

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        launcher.picker.alpha = 0.011
        return launcher.picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
