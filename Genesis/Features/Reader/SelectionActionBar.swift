import SwiftUI
import UIKit

/// Appears when verses are selected (tap or long-press a verse).
///
/// Compact by default, so it covers as little of the page as it can: one
/// row with the three highlight colors used most recently (and a stack that
/// opens the rest), then every action as a tile, sliding sideways where the
/// screen is narrow (the next tile peeks in at the edge). Swipe up (or tap
/// "Swipe up for more") for the full panel: every color, the eraser and all
/// the actions at once. Swipe down to go back to the row, and from the row
/// to clear the selection. The reference and the × sit at the top of the
/// reader instead (`SelectionReferenceBar`).
struct SelectionActionBar: View {
    let onImage: () -> Void
    let onNote: () -> Void
    let onCrossReferences: () -> Void
    let onExplain: () -> Void
    var onMemorise: (() -> Void)?
    /// Original words and commentary (nil when the data isn't in the app).
    var onWordStudy: (() -> Void)?
    /// A new prayer holding the selected verses (nil when the journal is hidden).
    var onPray: (() -> Void)?
    /// Downloaded study notes and commentaries on the verse (nil when the Study Library is hidden).
    var onStudy: (() -> Void)?

    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StudyAssistant.self) private var assistant
    @AppStorage(RecentHighlightColors.storageKey) private var recentColors = ""
    @State private var expanded = false
    @State private var copied = false
    @State private var highlightTrigger = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: expanded ? 14 : 10) {
            // A grabber says it can be swiped.
            Capsule()
                .fill(palette.secondaryText.opacity(0.35))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)
            if expanded {
                fullPanel
                    .transition(.opacity)
            } else {
                compactRow
                    .transition(.opacity)
            }
            moreOrLess
        }
        .foregroundStyle(palette.text)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: expanded ? 560 : 900)
        // The tiles slide inside the bar, never past its rounded edges.
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .simultaneousGesture(swipe)
        .sensoryFeedback(.impact(weight: .light), trigger: highlightTrigger)
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .sensoryFeedback(.selection, trigger: expanded)
        .onChange(of: reader.selection) { copied = false }
    }

    // MARK: Compact: one row

    private var compactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(RecentHighlightColors.shown(from: recentColors)) { color in
                        colorButton(color, size: 32)
                    }
                    moreColorsButton
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 60)
                .background(tileBackground)
                actionTiles(fill: false)
            }
            .padding(.horizontal, 12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// The other colors, as a little stack: opens the full panel.
    private var moreColorsButton: some View {
        let others = HighlightColor.allCases.filter { !RecentHighlightColors.shown(from: recentColors).contains($0) }
        return Button {
            setExpanded(true)
        } label: {
            ZStack {
                ForEach(Array(others.prefix(3).enumerated()), id: \.offset) { index, color in
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
                        .offset(x: CGFloat(index) * 7)
                }
            }
            .frame(width: 40, height: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("More Colors")
        .accessibilityIdentifier("selection.moreColors")
    }

    // MARK: Expanded: everything

    private var fullPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(HighlightColor.allCases) { color in
                    colorButton(color, size: 32)
                }
                Button {
                    reader.removeHighlightFromSelection()
                } label: {
                    Image(systemName: "eraser")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Remove highlight")
                .accessibilityIdentifier("selection.removeHighlight")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                actionTiles(fill: true)
            }
        }
        .padding(.horizontal, 16)
    }

    /// "Swipe up for more" in the row, "Show less" in the full panel. Also a
    /// button, for VoiceOver and anyone who'd rather tap.
    private var moreOrLess: some View {
        Button {
            setExpanded(!expanded)
        } label: {
            Label(expanded ? String(localized: "Show less") : String(localized: "Swipe up for more"),
                  systemImage: expanded ? "chevron.down" : "chevron.up")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(expanded ? "selection.less" : "selection.more")
    }

    // MARK: The actions (the same tiles in both)

    @ViewBuilder
    private func actionTiles(fill: Bool) -> some View {
        tile(String(localized: "Note", comment: "Verse selection action: add a note"), systemImage: "note.text.badge.plus", fill: fill, perform: onNote)
            .accessibilityIdentifier("selection.note")
        tile(String(localized: "Bookmark", comment: "Verse selection action: bookmark the verse"), systemImage: "bookmark", fill: fill) { reader.toggleBookmark() }
            .accessibilityIdentifier("selection.bookmark")
        tile(copied ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc", fill: fill) {
            UIPasteboard.general.string = reader.shareTextForSelection
            copied = true
        }
        .accessibilityIdentifier("selection.copy")
        ShareLink(item: reader.shareTextForSelection) {
            tileLabel(String(localized: "Share"), systemImage: "square.and.arrow.up", fill: fill)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selection.share")
        tile(String(localized: "Image", comment: "Verse selection action: make a shareable image"), systemImage: "photo", fill: fill, perform: onImage)
            .accessibilityIdentifier("selection.image")
        if let onPray {
            tile(String(localized: "Pray"), systemImage: "hands.and.sparkles", fill: fill, perform: onPray)
                .accessibilityLabel("Pray These Verses")
                .accessibilityIdentifier("selection.pray")
        }
        if let onMemorise {
            tile(String(localized: "Memorize"), systemImage: "brain.head.profile", fill: fill, perform: onMemorise)
                .accessibilityIdentifier("selection.memorise")
        }
        if let onWordStudy {
            tile(String(localized: "Word Study"), systemImage: "character.book.closed", fill: fill, perform: onWordStudy)
                .accessibilityIdentifier("selection.wordStudy")
        }
        if assistant.isEnabled {
            tile(String(localized: "Explain"), systemImage: "sparkles", fill: fill, perform: onExplain)
                .accessibilityIdentifier("selection.explain")
        }
        if reader.selection.count == 1 {
            tile(String(localized: "Related", comment: "Panel title: related passages (cross-references)"), systemImage: "arrow.triangle.branch", fill: fill, perform: onCrossReferences)
                .accessibilityIdentifier("selection.related")
        }
        if let onStudy {
            tile(String(localized: "Study", comment: "Verse selection action: study notes and commentaries on the verse"), systemImage: "books.vertical", fill: fill, perform: onStudy)
                .accessibilityIdentifier("selection.study")
        }
    }

    private func tile(_ title: String, systemImage: String, fill: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            tileLabel(title, systemImage: systemImage, fill: fill)
        }
        .buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, systemImage: String, fill: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(height: 22)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 10)
        .frame(minWidth: 64, maxWidth: fill ? .infinity : nil, minHeight: 60)
        .background(tileBackground)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(palette.secondaryText.opacity(0.1))
    }

    private func colorButton(_ color: HighlightColor, size: CGFloat) -> some View {
        Button {
            highlightTrigger += 1
            recentColors = RecentHighlightColors.recording(color, in: recentColors)
            reader.highlightSelection(color)
        } label: {
            Circle()
                .fill(color.swatch)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
                .overlay {
                    if differentiateWithoutColor {
                        Image(systemName: color.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
        }
        .accessibilityLabel("Highlight \(color.title)")
        .accessibilityIdentifier("selection.highlight.\(color.rawValue)")
    }

    // MARK: Swiping

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : Motion.easeOut(0.25)) { expanded = value }
    }

    /// Up opens the full panel; down closes it, or (from the row) clears
    /// the selection. The bar follows the finger a little; a sideways drag
    /// is the row sliding, so it's left alone.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !reduceMotion, abs(value.translation.height) > abs(value.translation.width) else { return }
                let y = value.translation.height
                dragOffset = y > 0 ? y : max(-16, y / 5)
            }
            .onEnded { value in
                let vertical = abs(value.translation.height) > abs(value.translation.width)
                let up = value.translation.height < -30 || value.predictedEndTranslation.height < -120
                let down = value.translation.height > 60 || value.predictedEndTranslation.height > 160
                if vertical && up && !expanded {
                    setExpanded(true)
                } else if vertical && down && expanded {
                    setExpanded(false)
                } else if vertical && down {
                    withAnimation(Motion.exit) { reader.clearSelection() }
                }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { dragOffset = 0 }
            }
    }
}

/// The selection's reference and a × to finish, at the top of the reader
/// while verses are selected (the bar along the bottom stays one row).
struct SelectionReferenceBar: View {
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(reader.selectedReference?.description(in: reader.translation.language) ?? "")
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("selection.reference")
            Text(reader.translation.abbreviation)
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)
            Button {
                reader.clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.text)
            .accessibilityLabel("Done selecting")
            .accessibilityIdentifier("selection.done")
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: Capsule())
    }
}
