import SwiftUI
import UIKit

/// A quiet section title used across Home and Library.
struct SectionHeader: View {
    let title: String
    var action: (title: String, perform: () -> Void)?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(palette.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action.title, action: action.perform)
                    .font(.subheadline)
            }
        }
    }
}

/// A soft rounded surface for grouping content.
struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    /// Themed background for a full screen.
    func themedScreen() -> some View { modifier(ThemedScreen()) }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.text)
    }
}

/// A verse with its reference, used in lists. Scripture is set in the reader's font.
struct VerseSnippet: View {
    let reference: String
    let text: String
    var highlight: HighlightColor?
    var terms: [String] = []
    var lineLimit: Int? = 3

    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let highlight {
                    Image(systemName: differentiateWithoutColor ? highlight.symbol : "circle.fill")
                        .font(.system(size: differentiateWithoutColor ? 10 : 8))
                        .foregroundStyle(highlight.swatch)
                        .accessibilityLabel("\(highlight.title) highlight")
                }
                Text(reference)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
            Text(attributedText)
                .font(settings.preferences.font.font(size: 17))
                .foregroundStyle(palette.text)
                .lineLimit(lineLimit)
                .lineSpacing(3)
        }
        .accessibilityElement(children: .combine)
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        guard !terms.isEmpty else { return attributed }
        for range in SearchHighlighter.matchRanges(in: text, terms: terms) {
            let lower = AttributedString.Index(range.lowerBound, within: attributed)
            let upper = AttributedString.Index(range.upperBound, within: attributed)
            guard let lower, let upper else { continue }
            attributed[lower..<upper].backgroundColor = palette.accent.opacity(0.22)
            attributed[lower..<upper].font = settings.preferences.font.font(size: 17, weight: .semibold)
        }
        return attributed
    }
}

/// Empty-state message in the app's quiet voice.
struct QuietEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

/// Device-level helpers that SwiftUI doesn't expose directly.
@MainActor
enum DeviceScreen {
    private static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// The window's safe area, which (unlike SwiftUI's) doesn't change when
    /// bars hide, so text never reflows as controls appear and disappear.
    static var safeAreaInsets: UIEdgeInsets {
        windowScene?.keyWindow?.safeAreaInsets ?? .zero
    }

    static var brightness: CGFloat {
        get { windowScene?.screen.brightness ?? 0.5 }
        set { windowScene?.screen.brightness = newValue }
    }
}
