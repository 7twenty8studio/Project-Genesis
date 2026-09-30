import Charts
import SwiftData
import SwiftUI

/// Reading statistics from the PRD: streaks, chapters and books, highlights,
/// reading time, favourite books and topics. Genesis Premium.
struct InsightsView: View {
    @Environment(ReadingProgress.self) private var progress
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @Query private var highlights: [Highlight]
    @Query private var notes: [Note]
    @Query(sort: \HighlightCollection.name) private var collections: [HighlightCollection]
    @State private var premium: PremiumFeature?

    private static let totalChapters = BibleBook.all.reduce(0) { $0 + $1.chapterCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                stats
                if entitlements.allows(.readingInsights) {
                    readingTime
                    favoriteBooks
                    favoriteTopics
                } else {
                    locked
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .themedScreen()
        .navigationTitle("Insights")
        .premiumSheet($premium)
    }

    private var stats: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            stat("\(progress.streak())", "day streak", "flame")
            stat("\(progress.chaptersRead.count) of \(Self.totalChapters)", "chapters read", "book.pages")
            stat("\(progress.booksCompleted) of 66", "books finished", "books.vertical")
            if entitlements.allows(.readingInsights) {
                stat("\(progress.longestStreak)", "longest streak", "trophy")
                stat("\(highlights.count)", "verses highlighted", "highlighter")
                stat("\(notes.filter { !$0.title.isEmpty || !$0.body.isEmpty }.count)", "notes written", "note.text")
                stat(Self.duration(progress.totalReadingTime), "total reading time", "clock")
                stat(Self.duration(TimeInterval(progress.dailyReadingTime(days: 7).map(\.seconds).reduce(0, +))), "this week", "calendar")
            }
        }
        .accessibilityIdentifier("insights.stats")
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(palette.accent)
            Text(value)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var readingTime: some View {
        let days = progress.dailyReadingTime(days: 14)
        return DetailSection(title: "Reading Time, Last Two Weeks") {
            Chart(days, id: \.day) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("Minutes", Double(entry.seconds) / 60)
                )
                .foregroundStyle(palette.accent)
                .cornerRadius(3)
            }
            .chartYAxisLabel("minutes")
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Reading time over the last two weeks: \(Self.duration(TimeInterval(days.map(\.seconds).reduce(0, +)))) in total")
        }
    }

    @ViewBuilder
    private var favoriteBooks: some View {
        let books = progress.favoriteBooks()
        if !books.isEmpty {
            DetailSection(title: "Favourite Books") {
                VStack(spacing: 12) {
                    ForEach(books, id: \.book.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.book.name).foregroundStyle(palette.text)
                                Spacer()
                                Text("\(entry.chapters) of \(entry.book.chapterCount) chapters")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            ProgressView(value: Double(entry.chapters), total: Double(entry.book.chapterCount))
                                .tint(palette.accent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteTopics: some View {
        let topics = collections
            .map { (name: $0.name, count: $0.highlights.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
        DetailSection(title: "Favourite Topics") {
            if topics.isEmpty {
                Text("Group highlights into collections in the Library, and your favourite topics appear here.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(topics), id: \.name) { topic in
                        HStack {
                            Text(topic.name).foregroundStyle(palette.text)
                            Spacer()
                            Text(topic.count == 1 ? "1 highlight" : "\(topic.count) highlights")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See your reading time, longest streak, favourite books and topics, and more with Premium.")
                .foregroundStyle(palette.secondaryText)
            Button("Unlock Insights") { premium = .readingInsights }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("insights.unlock")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
