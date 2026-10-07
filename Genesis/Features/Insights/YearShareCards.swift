import SwiftUI

// The extra shareable Year in Review cards (Premium, with Reading insights),
// drawn at 1080 × 1350 like `YearSummaryCard`. Numbers and book names only:
// no Scripture text.

/// Days in the Word: a dot for every day of the year, filled on days with reading.
struct YearDaysCard: View {
    let review: YearInReview
    let readingDays: Set<String>
    let theme: ReaderTheme
    let font: ReaderFont

    var body: some View {
        let palette = theme.palette
        YearCardPage(year: review.year, theme: theme, font: font) {
            VStack(alignment: .leading, spacing: 4) {
                Text(review.daysRead.formatted())
                    .font(font.font(size: 150, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("days in the Word")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.secondaryText)
            }
            dots(palette)
            HStack(alignment: .firstTextBaseline, spacing: 60) {
                figure(review.longestStreak.formatted(), String(localized: "day longest streak"), palette)
                if review.minutesRead > 0 {
                    figure(InsightsView.duration(TimeInterval(review.minutesRead * 60)), String(localized: "Time reading"), palette)
                }
            }
        }
    }

    private func dots(_ palette: ThemePalette) -> some View {
        let weeks = YearInReview.readingWeeks(year: review.year, readingDays: readingDays)
        return HStack(alignment: .top, spacing: 4.2) {
            ForEach(weeks.indices, id: \.self) { week in
                VStack(spacing: 4.2) {
                    ForEach(0..<7, id: \.self) { weekday in
                        dot(weeks[week][weekday], palette)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dot(_ read: Bool?, _ palette: ThemePalette) -> some View {
        switch read {
        case .some(true): Circle().fill(palette.accent).frame(width: 12, height: 12)
        case .some(false): Circle().fill(palette.separator.opacity(0.7)).frame(width: 12, height: 12)
        case .none: Color.clear.frame(width: 12, height: 12)
        }
    }
}

/// Chapters and books: the 66 books as a shelf of spines, each filled by how
/// much of it was read this year.
struct YearBooksCard: View {
    let review: YearInReview
    let chapters: Set<Int>
    let theme: ReaderTheme
    let font: ReaderFont

    var body: some View {
        let palette = theme.palette
        YearCardPage(year: review.year, theme: theme, font: font) {
            VStack(alignment: .leading, spacing: 4) {
                Text(review.chaptersRead.formatted())
                    .font(font.font(size: 150, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("chapters read")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.secondaryText)
            }
            shelf(palette)
            HStack(alignment: .firstTextBaseline, spacing: 60) {
                figure(review.booksOpened.formatted(), String(localized: "books opened"), palette)
                figure(review.booksFinished.formatted(), String(localized: "books finished"), palette)
            }
            if let book = review.topBook {
                Text("Most read: \(book.name)")
                    .font(font.font(size: 40))
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    /// Three rows of 22 spines: the Old Testament, then the New.
    private func shelf(_ palette: ThemePalette) -> some View {
        let shares = YearInReview.bookShares(chapters: chapters)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { row in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<22, id: \.self) { column in
                        let index = row * 22 + column
                        if shares.indices.contains(index) {
                            spine(shares[index], palette)
                        }
                    }
                }
            }
        }
    }

    private func spine(_ share: Double, _ palette: ThemePalette) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.separator.opacity(0.6))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.accent)
                .frame(height: 74 * share)
        }
        .frame(width: 32, height: 74)
    }
}

/// The shared frame of a card: paper, "MY YEAR WITH GENESIS", the year and
/// the card's own content.
private struct YearCardPage<Content: View>: View {
    let year: Int
    let theme: ReaderTheme
    let font: ReaderFont
    @ViewBuilder let content: Content

    var body: some View {
        let palette = theme.palette
        ZStack {
            Image(uiImage: PaperTexture.tile(for: theme))
                .resizable(resizingMode: .tile)
            VStack(alignment: .leading, spacing: 56) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MY YEAR WITH GENESIS")
                        .font(.system(size: 28, weight: .semibold))
                        .kerning(3)
                        .foregroundStyle(palette.accent)
                    Spacer()
                    Text(verbatim: String(year))
                        .font(font.font(size: 40, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                content
                Spacer(minLength: 0)
            }
            .padding(100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 1080, height: 1350)
        .clipped()
    }
}

/// A number over its label, for the foot of a card.
@MainActor
private func figure(_ value: String, _ label: String, _ palette: ThemePalette) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(value)
            .font(.system(size: 64, weight: .semibold, design: .serif))
            .foregroundStyle(palette.text)
        Text(label)
            .font(.system(size: 32))
            .foregroundStyle(palette.secondaryText)
    }
}
