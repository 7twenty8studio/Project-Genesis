import SwiftUI

/// A one-time sheet about new features.
struct WhatsNewView: View {
    let announcements: [WhatsNewAnnouncement]
    let onDone: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's New")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("whatsNew.title")
                        Text("Here's what has been added to Genesis.")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    ForEach(announcements) { announcement in
                        section(announcement)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: 560)
                .accessibilityIdentifier("whatsNew.continue")
            }
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func section(_ announcement: WhatsNewAnnouncement) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(announcement.title)
                .font(.headline)
                .foregroundStyle(palette.accent)
            ForEach(announcement.items) { item in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: item.systemImage)
                        .font(.title3)
                        .foregroundStyle(palette.accent)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("whatsNew.\(announcement.id)")
    }
}

/// Shows unseen announcements once, a moment after the app settles. Swiping
/// the sheet away counts as seen too.
struct WhatsNewPresenter: ViewModifier {
    let isReady: Bool

    @Environment(WhatsNewService.self) private var whatsNew
    @Environment(FeatureFlagService.self) private var flags
    @State private var showing: ShownAnnouncements?

    private struct ShownAnnouncements: Identifiable {
        let announcements: [WhatsNewAnnouncement]
        var id: String { announcements.map(\.id).joined(separator: ",") }
    }

    func body(content: Content) -> some View {
        content
            .task(id: checkKey) {
                guard isReady, showing == nil else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let pending = whatsNew.pending(flags: flags)
                if !pending.isEmpty { showing = ShownAnnouncements(announcements: pending) }
            }
            .sheet(item: $showing) { shown in
                WhatsNewView(announcements: shown.announcements) { showing = nil }
                    .onDisappear { whatsNew.markSeen(shown.announcements) }
            }
    }

    /// Re-checks when the app becomes ready or a switch changes.
    private var checkKey: String {
        "\(isReady)-\(FeatureFlag.allCases.filter { flags.isOn($0) }.map(\.rawValue))-\(whatsNew.seen.count)"
    }
}

extension View {
    func whatsNewSheet(isReady: Bool) -> some View {
        modifier(WhatsNewPresenter(isReady: isReady))
    }
}
