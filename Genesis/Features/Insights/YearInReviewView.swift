import SwiftData
import SwiftUI

/// "Your year with Genesis": a few pages to swipe through (days, time,
/// chapters, highlights, notes and prayers), ending with a summary to share.
/// Free for everyone; built from what's on this device.
struct YearInReviewView: View {
    let year: Int

    @Environment(ReadingProgress.self) private var progress
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Query private var highlights: [Highlight]
    @Query private var notes: [Note]
    @Query private var prayers: [Prayer]
    @State private var page = 0
    @State private var shareImage: UIImage?

    private var review: YearInReview {
        YearInReview.make(
            year: year,
            readingDays: progress.readingDays,
            readingSeconds: progress.readingSeconds,
            chapters: progress.chaptersByYear[String(year)] ?? [],
            highlights: highlights.map { .init(date: $0.createdAt, verse: $0.verse, color: $0.color) },
            notes: notes.filter { !$0.title.isEmpty || !$0.body.isEmpty }.map(\.createdAt),
            prayers: prayers.map { .init(created: $0.createdAt, answered: $0.answeredAt) }
        )
    }

    private var font: ReaderFont { settings.preferences.font }

    var body: some View {
        let review = self.review
        NavigationStack {
            Group {
                if review.hasActivity {
                    TabView(selection: $page) {
                        ForEach(Array(pages(review).enumerated()), id: \.offset) { index, content in
                            content
                                .padding(28)
                                .frame(maxWidth: 560)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                } else {
                    QuietEmptyState(
                        systemImage: "calendar",
                        title: String(localized: "Nothing to review yet"),
                        message: String(localized: "Read, highlight and pray with Genesis this year, and your year in review will appear here.")
                    )
                }
            }
            .background {
                Image(uiImage: PaperTexture.tile(for: theme))
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            }
            .navigationTitle(Text(verbatim: String(year)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("yearInReview.done")
                }
                if review.hasActivity, let shareImage {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview(Text("My \(String(year)) with Genesis"), image: Image(uiImage: shareImage))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("yearInReview.share")
                    }
                }
            }
            .task(id: review) {
                let renderer = ImageRenderer(content: YearSummaryCard(review: review, theme: theme, font: font).frame(width: 1080, height: 1350))
                renderer.scale = 1
                shareImage = renderer.uiImage
            }
        }
    }

    private var theme: ReaderTheme {
        let current = settings.preferences.theme.resolved(for: colorScheme)
        return current.isDark ? current : (current.hasPaperTexture ? current : .cream)
    }

    private func pages(_ review: YearInReview) -> [AnyView] {
        var pages: [AnyView] = []
        pages.append(AnyView(
            ReviewPage(symbol: "sparkles", eyebrow: String(localized: "Your year with Genesis"), big: String(year), detail: String(localized: "Swipe to look back on what you read, highlighted and prayed."), font: font)
        ))
        if review.daysRead > 0 {
            pages.append(AnyView(
                ReviewPage(
                    symbol: "calendar",
                    eyebrow: String(localized: "Days in the Word"),
                    big: review.daysRead.formatted(),
                    detail: review.longestStreak > 1
                        ? String(localized: "Your longest streak was \(review.longestStreak) days in a row.")
                        : String(localized: "Every day you opened the Bible counts."),
                    font: font
                )
            ))
        }
        if review.minutesRead > 0 {
            pages.append(AnyView(
                ReviewPage(
                    symbol: "clock",
                    eyebrow: String(localized: "Time reading"),
                    big: InsightsView.duration(TimeInterval(review.minutesRead * 60)),
                    detail: review.longestDay.map { String(localized: "Your longest day was \($0.formatted(.dateTime.month(.wide).day())), with \(review.longestDayMinutes) minutes.") } ?? "",
                    font: font
                )
            ))
        }
        if review.chaptersRead > 0 {
            pages.append(AnyView(
                ReviewPage(
                    symbol: "book.pages",
                    eyebrow: String(localized: "Chapters read"),
                    big: review.chaptersRead.formatted(),
                    detail: [
                        review.booksFinished > 0 ? String(localized: "You read \(review.booksFinished) books from beginning to end.") : nil,
                        review.topBook.map { String(localized: "You spent the most time in \($0.name).") },
                    ].compactMap { $0 }.joined(separator: " "),
                    font: font
                )
            ))
        }
        if review.highlights > 0 {
            pages.append(AnyView(
                ReviewPage(
                    symbol: "highlighter",
                    eyebrow: String(localized: "Verses highlighted"),
                    big: review.highlights.formatted(),
                    detail: review.mostHighlightedBook.map { String(localized: "Most of them in \($0.name).") } ?? "",
                    font: font,
                    swatch: review.favoriteColor?.swatch
                )
            ))
        }
        if review.notes > 0 || review.prayersAdded > 0 {
            pages.append(AnyView(
                ReviewPage(
                    symbol: "hands.and.sparkles",
                    eyebrow: String(localized: "Notes and prayers"),
                    big: (review.notes + review.prayersAdded).formatted(),
                    detail: review.prayersAnswered > 0
                        ? String(localized: "You wrote \(review.notes) notes and \(review.prayersAdded) prayers, and marked \(review.prayersAnswered) prayers answered.")
                        : String(localized: "You wrote \(review.notes) notes and \(review.prayersAdded) prayers."),
                    font: font
                )
            ))
        }
        pages.append(AnyView(
            VStack(spacing: 18) {
                YearSummaryCard(review: review, theme: theme, font: font)
                    .frame(width: 1080, height: 1350)
                    .scaleEffect(0.27)
                    .frame(width: 1080 * 0.27, height: 1350 * 0.27)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                    .accessibilityHidden(true)
                Text("Share your year with the button at the top.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        ))
        return pages
    }
}

/// One page: a symbol, a label, a big number and a sentence.
private struct ReviewPage: View {
    let symbol: String
    let eyebrow: String
    let big: String
    let detail: String
    let font: ReaderFont
    var swatch: Color?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.accent)
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(1.4)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 14) {
                if let swatch {
                    Circle().fill(swatch).frame(width: 26, height: 26)
                }
                Text(big)
                    .font(font.font(size: 64, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(font.font(size: 19))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The shareable summary, drawn at 1080 × 1350.
struct YearSummaryCard: View {
    let review: YearInReview
    let theme: ReaderTheme
    let font: ReaderFont

    var body: some View {
        let palette = theme.palette
        ZStack {
            Image(uiImage: PaperTexture.tile(for: theme))
                .resizable(resizingMode: .tile)
            VStack(alignment: .leading, spacing: 46) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MY YEAR WITH GENESIS")
                        .font(.system(size: 28, weight: .semibold))
                        .kerning(3)
                        .foregroundStyle(palette.accent)
                    Text(verbatim: String(review.year))
                        .font(font.font(size: 150, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                VStack(alignment: .leading, spacing: 30) {
                    row(review.daysRead.formatted(), String(localized: "days in the Word"), palette)
                    row(review.chaptersRead.formatted(), String(localized: "chapters read"), palette)
                    row(review.longestStreak.formatted(), String(localized: "day longest streak"), palette)
                    row(review.highlights.formatted(), String(localized: "verses highlighted"), palette)
                    if review.prayersAnswered > 0 {
                        row(review.prayersAnswered.formatted(), String(localized: "prayers answered"), palette)
                    }
                }
                Spacer()
                if let book = review.topBook {
                    Text("Most read: \(book.name)")
                        .font(font.font(size: 40))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 1080, height: 1350)
        .clipped()
    }

    private func row(_ value: String, _ label: String, _ palette: ThemePalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(value)
                .font(font.font(size: 84, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(.system(size: 36))
                .foregroundStyle(palette.secondaryText)
        }
    }
}
