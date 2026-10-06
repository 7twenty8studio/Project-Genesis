import SwiftUI

/// Where the Explore screens push to.
struct ExploreDestination: View {
    let route: ExploreRoute

    var body: some View {
        switch route {
        case let .event(id): EventDetailView(eventID: id)
        case let .person(id): PersonDetailView(personID: id)
        case let .place(id): PlaceDetailView(placeID: id)
        }
    }
}

/// A wrapping row of tappable name chips (people, places).
struct ChipFlow<Item: Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    let action: (Item) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                Button(title(item)) { action(item) }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(palette.text)
                    .background(palette.surface, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Verses that mention someone or somewhere: the reference and the verse text
/// from the local Bible, verbatim. Tapping opens the reader there.
struct VerseMentionList: View {
    let verses: [VerseID]
    var limit = 12

    @Environment(BibleLibrary.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var showsAll = false

    var body: some View {
        let shown = showsAll ? verses : Array(verses.prefix(limit))
        let texts = (try? library.current.verses(withIDs: shown)) ?? [:]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown, id: \.self) { verse in
                Button {
                    router.read(verse)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PassageReference(verse: verse).description)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        if let text = texts[verse]?.text {
                            Text(text)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(palette.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider()
            }
            if verses.count > shown.count {
                Button("Show all \(verses.count)") { showsAll = true }
                    .font(.subheadline)
                    .padding(.top, 10)
            }
            Text("Scripture \u{00B7} \(library.currentTranslation.abbreviation)")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 8)
        }
    }
}

/// A titled block on the detail screens.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(1.1)
                .foregroundStyle(palette.secondaryText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dictionary text, labelled so it's never mistaken for Scripture.
struct DictionaryText: View {
    let text: String

    @Environment(\.palette) private var palette
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(palette.text)
                .lineLimit(expanded ? nil : 6)
            if text.count > 400 {
                Button(expanded ? "Show less" : "Read more") { expanded.toggle() }
                    .font(.subheadline)
            }
            Text("From Easton's Bible Dictionary (1897)")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// A short placeholder when the bundled study data is missing.
struct StudyDataMissingView: View {
    var body: some View {
        QuietEmptyState(systemImage: "exclamationmark.triangle", title: String(localized: "Study data unavailable"), message: String(localized: "Reinstall Genesis to restore the timeline, maps and people."))
    }
}

/// A Premium part of a free page: what it offers and the way to unlock it.
struct PremiumTeaser: View {
    let message: String
    let feature: PremiumFeature

    @Environment(\.palette) private var palette
    @State private var premium: PremiumFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(message)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(palette.accent)
            }
            .font(.subheadline)
            Button("Unlock with Premium") { premium = feature }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityIdentifier("teaser.unlock")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .premiumSheet($premium)
    }
}
