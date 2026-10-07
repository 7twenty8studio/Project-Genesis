import SwiftUI

/// Home's evening card: opens Evening Sanctuary at the place the person is
/// reading, or shows Premium to free accounts. Home shows it after 6 pm
/// (`EveningSanctuary.showsHomeCard`).
struct EveningSanctuaryCard: View {
    @Environment(EntitlementService.self) private var entitlements
    @Environment(ReadingProgress.self) private var progress

    @State private var showsSanctuary = false
    @State private var premium: PremiumFeature?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "moon.stars")
                    .font(.title2)
                    .foregroundStyle(SanctuaryColors.candle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: PremiumFeature.eveningSanctuary.title)
                        .font(.headline)
                        .foregroundStyle(SanctuaryColors.text)
                    Text("Read by candlelight tonight, with your sounds and a sleep timer.")
                        .font(.subheadline)
                        .foregroundStyle(SanctuaryColors.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(SanctuaryColors.muted)
            }
            .padding(18)
            .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.sanctuary")
        .fullScreenCover(isPresented: $showsSanctuary) {
            EveningSanctuaryView(startVerse: progress.position)
        }
        .premiumSheet($premium)
    }

    /// The night room, with a little candle glow in the corner.
    private var background: some ShapeStyle {
        RadialGradient(
            colors: [SanctuaryColors.flame.opacity(0.28), SanctuaryColors.night],
            center: .bottomLeading,
            startRadius: 0,
            endRadius: 260
        )
    }

    private func open() {
        if entitlements.allows(.eveningSanctuary) {
            showsSanctuary = true
        } else {
            premium = .eveningSanctuary
        }
    }
}
