import SwiftUI
import WidgetKit

/// Memorise Scripture (Premium): the next passage to recall, as the first
/// letter of each word, and how many are waiting. Tapping opens a review.
struct MemoriseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Memorise", provider: SnapshotProvider()) { entry in
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
        let memorise = entry.snapshot.memorise
        Group {
            if let memorise, memorise.isUnlocked, let reference = memorise.reference {
                card(memorise, reference: reference)
            } else if memorise?.isUnlocked == true {
                message(String(localized: "Add a verse to memorise in Genesis."))
            } else {
                message(String(localized: "Memorise Scripture with Genesis Premium."))
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
        .widgetURL(GenesisLink.memorise)
    }

    @ViewBuilder
    private func card(_ memorise: WidgetSnapshot.Memorise, reference: String) -> some View {
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
                    Text(String(localized: "Memorise").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(WidgetPalette.accent)
                    Spacer()
                    if due > 0 {
                        Text("\(due) due")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.accent)
                    }
                }
                Text(reference)
                    .font(.system(family == .systemSmall ? .headline : .title3, design: .serif, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(memorise.hint ?? "")
                    .font(.system(family == .systemSmall ? .footnote : .body, design: .serif))
                    .foregroundStyle(WidgetPalette.secondary)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(due > 0 ? String(localized: "Tap to review") : String(localized: "All caught up"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
            }
        }
    }

    private func message(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(WidgetPalette.accent)
            Text(text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(WidgetPalette.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
