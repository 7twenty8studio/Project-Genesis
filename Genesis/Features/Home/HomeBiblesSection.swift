import SwiftUI

/// Home's Bibles on This Device: a language picker (when there's more than
/// one) and that language's Bibles, the one being read first, a few at a
/// time with "Show all", so the card stays short as people add Bibles.
struct HomeBiblesSection: View {
    @Binding var premium: PremiumFeature?
    @Binding var showsBibles: Bool

    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The language picked here; nil follows the Bible being read.
    @State private var language: String?
    @State private var expanded = false

    var body: some View {
        let shelf = ReadingLibrary.shelf(library.translations, current: library.currentTranslation, language: language, expanded: expanded)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Bibles on This Device"), action: (String(localized: "Get More"), { showsBibles = true }))
            VStack(alignment: .leading, spacing: 0) {
                if shelf.showsLanguages {
                    HomeBibleLanguagePicker(groups: shelf.groups, selection: shelf.language) { choice in
                        withAnimation(Motion.change(reduceMotion: reduceMotion)) {
                            language = choice
                            expanded = false
                        }
                    }
                    .padding(.bottom, 6)
                }
                ForEach(shelf.shown) { translation in
                    if translation.id != shelf.shown.first?.id {
                        Divider().overlay(palette.separator)
                    }
                    HomeBibleRow(translation: translation, groupLanguage: shelf.language) {
                        if library.isLocked(translation) {
                            premium = .premiumBibles
                        } else {
                            router.reader.switchTranslation(to: translation)
                        }
                    }
                    .transition(.opacity)
                }
                if shelf.hiddenCount > 0 || expanded {
                    Divider().overlay(palette.separator)
                    Button {
                        withAnimation(Motion.change(reduceMotion: reduceMotion)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? String(localized: "Show less") : String(localized: "Show all \(shelf.shown.count + shelf.hiddenCount)"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.bibles.showAll")
                }
            }
            .card()
        }
        // A new Bible to read brings its own language back to the front.
        .onChange(of: library.currentTranslation) {
            language = nil
            expanded = false
        }
    }
}

/// The languages with a Bible on this device, as buttons that wrap onto a
/// second line rather than scroll out of sight, each with its count.
private struct HomeBibleLanguagePicker: View {
    let groups: [TranslationGroup]
    let selection: String
    let choose: (String) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(groups) { group in
                let isSelected = group.language == selection
                Button {
                    choose(group.language)
                } label: {
                    HStack(spacing: 6) {
                        Text(AppLanguage.displayName(group.language))
                            .font(.subheadline.weight(.medium))
                        Text(group.translations.count, format: .number)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                    .foregroundStyle(isSelected ? palette.surface : palette.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(isSelected ? palette.accent : palette.accent.opacity(0.1), in: Capsule())
                    // A bigger target than the chip draws.
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.displayName(group.language))
                .accessibilityValue(String(localized: "\(group.translations.count) on this device"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("home.bibles.language.\(group.language)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Language"))
    }
}

/// One Bible: its abbreviation, name and whether it's offline; a checkmark
/// on the one being read, a lock on a Premium Bible.
private struct HomeBibleRow: View {
    let translation: Translation
    /// The picker's language: a regional Bible (O Livro, pt-PT, under
    /// Português) names its region.
    let groupLanguage: String
    let open: () -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var abbreviationWidth: CGFloat = 60

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        abbreviation
                        details
                    }
                } else {
                    abbreviation
                        .frame(width: abbreviationWidth, alignment: .leading)
                    details
                }
                Spacer(minLength: 8)
                badge
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(translation.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isLocked ? PremiumFeature.premiumBibles.title : String(localized: "Opens in the reader"))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("home.bibles.\(translation.id)")
    }

    private var isCurrent: Bool { translation == library.currentTranslation }
    private var isLocked: Bool { library.isLocked(translation) }
    private var region: String? {
        translation.language == groupLanguage ? nil : AppLanguage.regionalName(translation.language)
    }

    private var status: String {
        library.isAvailableOffline(translation) ? String(localized: "Available offline") : String(localized: "Not downloaded")
    }

    private var abbreviation: some View {
        Text(translation.abbreviation)
            .font(.system(.subheadline, design: .serif, weight: .bold))
            .foregroundStyle(palette.accent)
            // One line: "RV1909" wrapped to "RV19 / 09".
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(translation.name)
                .foregroundStyle(palette.text)
            Text(region.map { "\($0) · \(status)" } ?? status)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ViewBuilder private var badge: some View {
        if isCurrent {
            Image(systemName: "checkmark")
                .foregroundStyle(palette.accent)
        } else if isLocked {
            Image(systemName: "lock")
                .foregroundStyle(palette.secondaryText)
        }
    }

    /// Read after the name: the abbreviation, region, status, and whether
    /// it's the Bible being read.
    private var accessibilityValue: String {
        var parts = [translation.abbreviation]
        if let region { parts.append(region) }
        parts.append(status)
        if isCurrent { parts.append(String(localized: "Current translation")) }
        return parts.joined(separator: ", ")
    }
}

/// Lays chips out in rows, wrapping to the next line when one doesn't fit.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
