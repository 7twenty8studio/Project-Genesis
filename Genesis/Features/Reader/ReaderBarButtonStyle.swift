import SwiftUI

/// The reader's floating bars (`ReaderControls`, `SelectionReferenceBar`)
/// draw their buttons themselves, so they keep the size the bar was laid out
/// for whatever the iPhone's accessibility settings are.
///
/// With Settings › Accessibility › Display & Text Size › Button Shapes on,
/// iOS gives every borderless button its own padded backing, which made each
/// one about 12 pt bigger, squeezed the chapter name to a letter and pushed
/// the bar over the page's heading. Here the shape is drawn inside the
/// button's own frame instead: still a visible shape, never a bigger button.
struct ReaderBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ReaderBarButton(configuration: configuration)
    }
}

private struct ReaderBarButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityShowButtonShapes) private var showsShapes
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    var body: some View {
        configuration.label
            .background {
                if showsShapes {
                    Capsule()
                        .fill(palette.text.opacity(configuration.isPressed ? 0.16 : 0.08))
                        .padding(2)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The reader bars' buttons and menus: `ReaderBarButtonStyle`, text
    /// capped at the largest standard size (the bar's height is fixed, as
    /// UIKit's bars do) with the Large Content Viewer for larger sizes.
    func readerBarButtons() -> some View {
        self
            .buttonStyle(ReaderBarButtonStyle())
            .menuStyle(.button)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
