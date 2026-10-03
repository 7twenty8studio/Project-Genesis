import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Today's reading, with a tick (Premium)

struct TodaysReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaysReading", provider: SnapshotProvider()) { entry in
            TodaysReadingView(entry: entry)
        }
        .configurationDisplayName("Today's Reading")
        .description("Today's reading from your plan. Tick it off when you're done.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodaysReadingView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        Group {
            if snapshot.isPremium != true {
                prompt(String(localized: "Tick off your daily reading with Genesis Premium."), link: GenesisLink.plans)
            } else if let plan = snapshot.plan {
                planView(plan)
            } else {
                prompt(String(localized: "Start a reading plan in Genesis to see today's reading here."), link: GenesisLink.plans)
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func planView(_ plan: WidgetSnapshot.Plan) -> some View {
        let done = plan.isTodayComplete
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Today's Reading").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1)
                .foregroundStyle(WidgetPalette.accent)
            Text(plan.todayTitle)
                .font(.system(family == .systemSmall ? .headline : .title3, design: .serif, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .strikethrough(done, color: WidgetPalette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(plan.title)
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                if let id = plan.enrollmentID {
                    let day = plan.scheduledDay ?? plan.dayNumber
                    Button(intent: TogglePlanDayIntent(enrollmentID: id, day: day, completed: !done)) {
                        Label(done ? String(localized: "Done") : String(localized: "Mark Read"), systemImage: done ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WidgetPalette.accent)
                }
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Gauge(value: plan.fractionComplete) {
                        Text("Plan")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(WidgetPalette.accent)
                    .frame(width: 90)
                }
            }
        }
        .widgetURL(GenesisLink.plans)
    }

    private func prompt(_ text: String, link: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(WidgetPalette.accent)
            Text(text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(WidgetPalette.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(link)
    }
}

// MARK: - Listening Live Activity (Premium)

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningActivityAttributes.self) { context in
            ListeningLockScreenView(context: context)
                .activityBackgroundTint(WidgetPalette.background)
                .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "headphones")
                        .foregroundStyle(WidgetPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayPauseButton(isPlaying: context.state.isPlaying)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.reference)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let text = context.state.verseText {
                        Text(text)
                            .font(.system(.footnote, design: .serif))
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                Image(systemName: "headphones")
                    .foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                Text(context.state.reference)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "headphones" : "pause.fill")
                    .foregroundStyle(WidgetPalette.accent)
            }
            .widgetURL(GenesisLink.read(0))
        }
    }
}

private struct ListeningLockScreenView: View {
    let context: ActivityViewContext<ListeningActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .foregroundStyle(WidgetPalette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.reference)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(WidgetPalette.text)
                    Text(context.attributes.translation)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                }
                Spacer()
                PlayPauseButton(isPlaying: context.state.isPlaying)
                Button(intent: NextChapterIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WidgetPalette.text)
                .accessibilityLabel(Text("Next chapter"))
            }
            if let text = context.state.verseText {
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(3)
            }
            if let progress = context.state.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(WidgetPalette.accent)
            }
        }
        .padding(16)
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool

    var body: some View {
        Button(intent: ToggleListeningIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(WidgetPalette.accent)
        .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
    }
}
