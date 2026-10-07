import SwiftUI

/// The journal as a timeline: one section per month, newest first, with
/// each prayer where it was asked and, once answered, where the answer came.
struct PrayerTimelineSections: View {
    let prayers: [Prayer]
    let onOpen: (Prayer) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let byID = Dictionary(prayers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let months = PrayerTimeline.months(prayers.map(\.facts))
        if months.isEmpty {
            QuietEmptyState(
                systemImage: "calendar",
                title: String(localized: "Your story with God"),
                message: String(localized: "Prayers and answers appear here by month, so you can look back on God's faithfulness.")
            )
            .listRowBackground(Color.clear)
        }
        ForEach(months) { month in
            Section {
                ForEach(month.entries) { entry in
                    if let prayer = byID[entry.prayerID] {
                        Button {
                            onOpen(prayer)
                        } label: {
                            PrayerTimelineRow(prayer: prayer, kind: entry.kind)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            } header: {
                Text(month.start, format: .dateTime.month(.wide).year())
            }
        }
    }
}

/// A prayer asked, or a prayer answered (with when it was asked).
struct PrayerTimelineRow: View {
    let prayer: Prayer
    let kind: PrayerTimeline.Entry.Kind

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .answered ? "checkmark.seal.fill" : "hands.and.sparkles")
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                caption
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Text(prayer.displayTitle)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                if kind == .answered, let note = prayer.answerNote, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(kind == .answered ? "prayer.timeline.answered" : "prayer.timeline.asked")
    }

    private var caption: Text {
        let asked = prayer.createdAt.formatted(.dateTime.month(.abbreviated).day())
        if kind == .answered, let answeredAt = prayer.answeredAt {
            let answered = answeredAt.formatted(.dateTime.month(.abbreviated).day())
            return Text("Answered \(answered) · asked \(asked)")
        }
        return Text("Asked \(asked) · \(prayer.category.title)")
    }
}
