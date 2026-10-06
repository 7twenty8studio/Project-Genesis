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
            } else if let plan = snapshot.plan, !Calendar.current.isDate(snapshot.generatedAt, inSameDayAs: entry.date) {
                // Written yesterday: today's reading isn't known until the app runs.
                prompt(String(localized: "Open Genesis to see today's reading from \(plan.title)."), link: GenesisLink.plans)
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

// MARK: - Group progress (Premium)

struct GroupProgressEntry: TimelineEntry {
    let date: Date
    let group: GroupWidgetSnapshot?
    let isPremium: Bool
}

struct GroupProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroupProgressEntry {
        GroupProgressEntry(date: .now, group: .placeholder, isPremium: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GroupProgressEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GroupProgressEntry>) -> Void) {
        // The app refreshes it when the group changes; check back hourly too.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entry() -> GroupProgressEntry {
        GroupProgressEntry(date: .now, group: GroupWidgetSnapshot.load(), isPremium: WidgetSnapshot.load()?.isPremium == true)
    }
}

/// How a group is getting on with its reading plan: who has read today and
/// everyone's progress bar.
struct GroupProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GroupWidgetSnapshot.widgetKind, provider: GroupProgressProvider()) { entry in
            GroupProgressView(entry: entry)
        }
        .configurationDisplayName("Group Progress")
        .description("Your group's reading plan: who has read today and how far everyone has come.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GroupProgressView: View {
    let entry: GroupProgressEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.isPremium {
                note(String(localized: "Follow your group's reading with Genesis Premium."))
            } else if let group = entry.group {
                content(group)
            } else {
                note(String(localized: "Open a group with a reading plan in Genesis to see its progress here."))
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    @ViewBuilder
    private func content(_ group: GroupWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.groupName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1)
                .foregroundStyle(WidgetPalette.accent)
                .lineLimit(1)
            if family == .systemSmall {
                Spacer(minLength: 0)
                Text("\(group.readTodayCount) of \(group.memberCount)")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                Text("read today")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 0)
                if group.day > 0 {
                    Text("Day \(group.day) of \(group.dayCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.dayTitle ?? group.planTitle)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(WidgetPalette.text)
                        .lineLimit(1)
                    Spacer()
                    if group.day > 0 {
                        Text("Day \(group.day) of \(group.dayCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
                ForEach(Array(group.members.prefix(family == .systemLarge ? 8 : 3).enumerated()), id: \.offset) { _, member in
                    HStack(spacing: 8) {
                        Image(systemName: member.readToday ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(member.readToday ? WidgetPalette.accent : WidgetPalette.secondary)
                        Text(member.name)
                            .font(.caption)
                            .foregroundStyle(WidgetPalette.text)
                            .lineLimit(1)
                            .frame(width: 70, alignment: .leading)
                        ProgressView(value: member.fraction)
                            .tint(WidgetPalette.accent)
                    }
                }
                Spacer(minLength: 0)
                Text("\(group.readTodayCount) of \(group.memberCount) read today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
            }
        }
        .widgetURL(URL(string: "\(GenesisLink.scheme)://group/\(group.groupID.uuidString)"))
    }

    private func note(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.3")
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
