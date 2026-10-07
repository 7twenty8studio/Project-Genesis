import SwiftUI
import UIKit

/// Keeps the screen from locking while Church Mode is on and the editor is
/// showing with the app in front; puts the idle timer back as it was when
/// any of those stops (closing the editor, leaving the app, turning Church
/// Mode off). The rule lives in `ScreenAwakeKeeper`.
struct ChurchModeScreenAwake: ViewModifier {
    let churchMode: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var keeper = ScreenAwakeKeeper()
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isShowing = true
                apply(showing: true, churchMode: churchMode, phase: scenePhase)
            }
            .onDisappear {
                isShowing = false
                apply(showing: false, churchMode: churchMode, phase: scenePhase)
            }
            .onChange(of: churchMode) { _, on in apply(showing: isShowing, churchMode: on, phase: scenePhase) }
            .onChange(of: scenePhase) { _, phase in apply(showing: isShowing, churchMode: churchMode, phase: phase) }
    }

    private func apply(showing: Bool, churchMode: Bool, phase: ScenePhase) {
        let keepAwake = ScreenAwakeKeeper.shouldKeepAwake(churchMode: churchMode, isShowing: showing, isActive: phase == .active)
        let application = UIApplication.shared
        if let value = keeper.update(keepAwake: keepAwake, current: application.isIdleTimerDisabled) {
            application.isIdleTimerDisabled = value
        }
    }
}
