import ReplayKit
import SwiftUI

@main
struct MirrorApp: App {
    var body: some Scene {
        WindowGroup { MirrorScreen() }
    }
}

/// One screen: this iPhone's ID (its OBS source) and the button that starts
/// the broadcast. The broadcast itself runs in the extension (SampleHandler),
/// so it keeps going while Versely or any other app is open.
struct MirrorScreen: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Versely Mirror")
                .font(.largeTitle.bold())
            VStack(spacing: 6) {
                Text("This iPhone's ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Mirror.deviceID)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }
            BroadcastButton()
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.red.opacity(0.12)))
            Text("Tap the button, choose Versely Mirror, then Start Broadcast. Open Versely and play. To stop, tap the red bar or the clock at the top.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Room \(Mirror.room)")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
            Button("Copy OBS link") { UIPasteboard.general.string = Mirror.obsLink }
                .font(.footnote)
        }
        .padding(32)
    }
}

/// The system's broadcast picker, opening straight on our extension.
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 88, height: 88))
        picker.preferredExtension = "com.7twenty8studio.versely.mirror.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
