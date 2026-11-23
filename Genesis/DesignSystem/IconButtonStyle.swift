import SwiftUI

/// Small icon buttons (and swatches) that sit at a fixed size in a row or a
/// floating bar: the reader's controls, the listening bars, Home's Search,
/// Settings and Account, and the like.
///
/// With Settings › Accessibility › Display & Text Size › Button Shapes on,
/// iOS gives every borderless button its own padded backing *outside* its
/// frame, which made each of these about 12 pt bigger: the reader's bar
/// grew over the page's heading and squeezed the chapter name to a letter.
/// This style draws the shape *inside* the button's own frame instead, so
/// people who rely on Button Shapes still see one, and nothing grows.
/// `drawsShape: false` is for buttons that already look like a shape (a
/// colour swatch, a glass circle).
struct IconButtonStyle: ButtonStyle {
    var drawsShape = true

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, drawsShape: drawsShape)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let drawsShape: Bool

    @Environment(\.accessibilityShowButtonShapes) private var showsShapes
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    var body: some View {
        configuration.label
            .background {
                if showsShapes && drawsShape {
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
    /// `IconButtonStyle` for every button and menu inside (an inner
    /// `.buttonStyle` still wins).
    func iconButtons(drawsShape: Bool = true) -> some View {
        self
            .buttonStyle(IconButtonStyle(drawsShape: drawsShape))
            .menuStyle(.button)
    }

    /// The reader's floating bars: `iconButtons()`, with text capped at the
    /// largest standard size (the bar's height is fixed, as UIKit's bars
    /// are); their buttons offer the Large Content Viewer instead.
    func readerBarButtons() -> some View {
        self
            .iconButtons()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// An icon-only button's Large Content Viewer (long press at the
    /// accessibility text sizes, where its icon stays capped).
    func largeContent(_ systemImage: String, _ label: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Image(systemName: systemImage)
        } label: {
            Text(label)
        }
    }
}
