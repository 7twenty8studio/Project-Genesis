import SwiftUI
import WidgetKit

/// Memorise Scripture (Premium): the next passage to recall, as the first
/// letter of each word, and how many are waiting. Tapping opens a review.
struct MemoriseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.memorise.rawValue, provider: SnapshotProvider()) { entry in
            MemoriseWidgetView(entry: entry)
        }
        .configurationDisplayName("Memorise")
        .description("Recall a verse you're learning by heart.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct MemoriseWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.memorise?.isHidden == true {
            hiddenView(WidgetColors(entry.snapshot))
        } else if entry.snapshot.unlocks(.memorise, in: family) {
            memoriseView(WidgetColors(entry.snapshot))
        } else {
            PremiumLockedView(message: String(localized: "Memorise Scripture with Genesis Premium."), symbol: "brain.head.profile")
        }
    }

    /// Memorise is switched off in Genesis: say so, and open the app's switch.
    private func hiddenView(_ colors: WidgetColors) -> some View {
        Group {
            if family == .accessoryRectangular {
                Label(String(localized: "Memorise is turned off"), systemImage: "brain.head.profile")
                    .font(.caption)
            } else {
                message(String(localized: "Memorise Scripture is turned off in Genesis."), colors: colors)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear } else { WidgetBackground(colors: colors) }
        }
        .widgetURL(GenesisLink.memorise)
    }

    private func memoriseView(_ colors: WidgetColors) -> some View {
        let memorise = entry.snapshot.memorise
        return Group {
            if let memorise, let reference = memorise.reference {
                card(memorise, reference: reference, colors: colors)
            } else {
                message(String(localized: "Add a verse to memorise in Genesis."), colors: colors)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear } else { WidgetBackground(colors: colors) }
        }
        .widgetURL(GenesisLink.memorise)
    }

    @ViewBuilder
    private func card(_ memorise: WidgetSnapshot.Memorise, reference: String, colors: WidgetColors) -> some View {
        let due = memorise.dueCount(on: entry.date)
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(reference, systemImage: "brain.head.profile").font(.headline)
                Text(memorise.hint ?? "").font(.caption).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: String(localized: "Memorise"), color: colors.accent)
                    Spacer()
                    if due > 0 {
                        Text("\(due) due")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                Text(reference)
                    .font(.system(family == .systemSmall ? .headline : .title3, design: .serif, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(memorise.hint ?? "")
                    .font(.system(family == .systemSmall ? .footnote : .body, design: .serif))
                    .foregroundStyle(colors.secondary)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(due > 0 ? String(localized: "Tap to review") : String(localized: "All caught up"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.secondary)
            }
        }
    }

    private func message(_ text: String, colors: WidgetColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(colors.accent)
            Text(text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(colors.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
