import SwiftUI
import UIKit

/// The chapter-complete moment: a gold ribbon bookmark drops in from the top
/// edge with a soft haptic, then lifts away (about 1.5 s in all). It sits in
/// the top corner, never takes touches, and with Reduce Motion simply fades.
/// Part of the deluxe look (`.premiumThemes`).
struct ChapterMomentOverlay: View {
    /// Shows only the moments raised for this screen.
    let place: ChapterMoments.Place
    /// Where the screen is drawn edge to edge, the space the status bar
    /// takes: the ribbon hangs from the very top, past it.
    var topInset: CGFloat = 0
    /// Off where the screen already plays its own success haptic.
    var playsHaptic = true

    @Environment(EntitlementService.self) private var entitlements
    @Environment(BibleLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown: ChapterMoments.Moment?
    @State private var isVisible = false

    private var moments: ChapterMoments { ChapterMoments.shared }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let shown, isVisible {
                ChapterRibbon(title: title(for: shown.kind), detail: detail(for: shown.kind), topInset: topInset, shines: !reduceMotion)
                    .padding(.trailing, 24)
                    .transition(ribbonTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.success, trigger: shown?.id) { _, new in
            playsHaptic && new != nil
        }
        .task(id: moments.current?.id) {
            await present(moments.current)
        }
    }

    private var ribbonTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private func present(_ moment: ChapterMoments.Moment?) async {
        guard let moment, moment.place == place, moment.isFresh() else {
            // Another screen's moment replaced ours mid-way: put ours away.
            if isVisible { withAnimation(.easeIn(duration: 0.3)) { isVisible = false } }
            return
        }
        guard entitlements.allows(.premiumThemes) else {
            moments.dismiss(moment)
            return
        }
        shown = moment
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2)) {
            isVisible = true
        }
        UIAccessibility.post(notification: .announcement, argument: title(for: moment.kind))
        try? await Task.sleep(for: .seconds(1.05))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.35)) { isVisible = false }
        try? await Task.sleep(for: .seconds(0.4))
        moments.dismiss(moment)
    }

    private func title(for kind: ChapterMoments.Kind) -> String {
        switch kind {
        case .chapter: String(localized: "Chapter complete")
        case .planDay: String(localized: "Day complete")
        }
    }

    private func detail(for kind: ChapterMoments.Kind) -> String {
        switch kind {
        case let .chapter(chapter): chapter.description(in: library.currentTranslation.language)
        case let .planDay(day): String(localized: "Day \(day)")
        }
    }
}

/// A muted gold ribbon hanging from the top edge, with a small label beside it.
private struct ChapterRibbon: View {
    let title: String
    let detail: String
    let topInset: CGFloat
    let shines: Bool

    @Environment(\.palette) private var palette
    @State private var shine = false

    private static let goldDark = Color(uiColor: UIColor(hex: 0x8C6D3F))
    private static let gold = Color(uiColor: UIColor(hex: 0xB8955A))
    private static let goldLight = Color(uiColor: UIColor(hex: 0xDCC28E))

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.text)
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 4)

            ribbon
        }
    }

    private var ribbon: some View {
        RibbonShape()
            .fill(LinearGradient(colors: [Self.goldDark, Self.goldLight, Self.gold, Self.goldDark], startPoint: .leading, endPoint: .trailing))
            .overlay {
                // One soft glint running down the ribbon.
                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .offset(y: shine ? topInset + 40 : -(topInset + 40))
                    .mask(RibbonShape())
            }
            .frame(width: 24, height: topInset + 58)
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .onAppear {
                guard shines else { return }
                withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { shine = true }
            }
    }
}

/// A ribbon bookmark: a strip with a notch cut into its lower end.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(rect.width * 0.5, rect.height * 0.3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
