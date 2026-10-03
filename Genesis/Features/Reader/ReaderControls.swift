import SwiftUI
import TipKit

/// Floating controls shown when the reader is tapped: chapter navigation,
/// translation, bookmark and reading settings.
struct ReaderControls: View {
    let showsCompanionToggle: Bool
    let onChapterPicker: () -> Void
    let onSettings: () -> Void
    let onStudy: () -> Void
    let onListen: () -> Void
    let onMoreBibles: () -> Void
    let onToggleCompanion: () -> Void

    @Environment(ReaderViewModel.self) private var reader
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(StudyAssistant.self) private var assistant
    @Environment(AudioPlayerService.self) private var audio
    @Environment(FeaturePreferences.self) private var features

    var body: some View {
        // Narrow reading areas (a phone, iPad Split View) get tighter buttons,
        // then a "More" menu, instead of squeezing the chapter name away.
        ViewThatFits(in: .horizontal) {
            row(iconWidth: 36, overflow: false)
            row(iconWidth: 30, overflow: false)
            row(iconWidth: 30, overflow: true)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 16)
    }

    private func row(iconWidth: CGFloat, overflow: Bool) -> some View {
        HStack(spacing: iconWidth < 36 ? 6 : 10) {
            navigation(iconWidth: iconWidth)
            Spacer(minLength: 0)
            tools(iconWidth: iconWidth, overflow: overflow)
        }
    }

    private func navigation(iconWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            iconButton("chevron.left", label: String(localized: "Previous chapter"), width: iconWidth, enabled: reader.chapterID.previous != nil) {
                reader.goToPreviousChapter()
            }
            .accessibilityIdentifier("reader.previousChapter")
            Button(action: onChapterPicker) {
                Text(reader.chapterID.description)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
            }
            .accessibilityHint("Choose a book and chapter")
            .accessibilityIdentifier("reader.chapterButton")
            iconButton("chevron.right", label: String(localized: "Next chapter"), width: iconWidth, enabled: reader.chapterID.next != nil) {
                reader.goToNextChapter()
            }
            .accessibilityIdentifier("reader.nextChapter")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }

    private func tools(iconWidth: CGFloat, overflow: Bool) -> some View {
        HStack(spacing: 2) {
            translationMenu

            if !overflow {
                bookmarkButton(width: iconWidth)
            }

            if features.isOn(.listen) {
                let listening = audio.isPlaying && audio.chapter == reader.chapterID
                iconButton(listening ? "pause.circle" : "headphones", label: listening ? String(localized: "Pause listening") : String(localized: "Listen to this chapter"), width: iconWidth, action: onListen)
                    .accessibilityIdentifier("reader.listen")
                    .popoverTip(GenesisTips.listen)
            }

            if assistant.isEnabled && !overflow {
                iconButton("sparkles", label: String(localized: "Study this chapter"), width: iconWidth, action: onStudy)
                    .accessibilityIdentifier("reader.study")
            }

            iconButton("textformat.size", label: String(localized: "Reading settings"), width: iconWidth, action: onSettings)
                .accessibilityIdentifier("reader.settings")

            if showsCompanionToggle && !overflow {
                iconButton("sidebar.right", label: String(localized: "Toggle study panel"), width: iconWidth, action: onToggleCompanion)
            }

            if overflow {
                moreMenu(width: iconWidth)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }

    private var translationMenu: some View {
        Menu {
            ForEach(library.translations) { translation in
                Button {
                    reader.switchTranslation(to: translation)
                } label: {
                    if translation == reader.translation {
                        Label("\(translation.abbreviation) · \(translation.name)", systemImage: "checkmark")
                    } else {
                        Text("\(translation.abbreviation) · \(translation.name)")
                    }
                }
                .accessibilityIdentifier("reader.translation.\(translation.id)")
            }
            Divider()
            // Read two Bibles side by side.
            Menu("Read in Parallel", systemImage: "rectangle.split.2x1") {
                ForEach(library.translations.filter { $0 != reader.translation }) { other in
                    Button {
                        reader.readInParallel(with: other)
                    } label: {
                        if other.id == reader.parallelTranslation?.id {
                            Label("\(other.abbreviation) · \(other.name)", systemImage: "checkmark")
                        } else {
                            Text("\(other.abbreviation) · \(other.name)")
                        }
                    }
                    .accessibilityIdentifier("reader.parallel.\(other.id)")
                }
                if reader.parallelTranslation != nil {
                    Divider()
                    Button("Stop Parallel Reading", systemImage: "rectangle") {
                        reader.readInParallel(with: nil)
                    }
                    .accessibilityIdentifier("reader.parallel.off")
                }
            }
            .accessibilityIdentifier("reader.parallelMenu")
            Button("More Bibles\u{2026}", systemImage: "arrow.down.circle", action: onMoreBibles)
                .accessibilityIdentifier("reader.moreBibles")
        } label: {
            Text(reader.parallelTranslation.map { "\(reader.translation.abbreviation) | \($0.abbreviation)" } ?? reader.translation.abbreviation)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(minWidth: 40, minHeight: 36)
        }
        .accessibilityLabel("Translation, \(reader.translation.name)")
        .accessibilityIdentifier("reader.translation")
    }

    private func bookmarkButton(width: CGFloat) -> some View {
        let bookmarked = reader.isCurrentChapterBookmarked
        return iconButton(bookmarked ? "bookmark.fill" : "bookmark", label: bookmarked ? String(localized: "Remove bookmark") : String(localized: "Add bookmark"), width: width) {
            reader.toggleBookmark()
        }
        .sensoryFeedback(.selection, trigger: bookmarked)
        .accessibilityIdentifier("reader.bookmark")
    }

    /// The less frequent actions, when the row is too narrow for them all.
    private func moreMenu(width: CGFloat) -> some View {
        Menu {
            let bookmarked = reader.isCurrentChapterBookmarked
            Button(bookmarked ? "Remove Bookmark" : "Add Bookmark", systemImage: bookmarked ? "bookmark.fill" : "bookmark") {
                reader.toggleBookmark()
            }
            .accessibilityIdentifier("reader.bookmark")
            if assistant.isEnabled {
                Button("Study This Chapter", systemImage: "sparkles", action: onStudy)
                    .accessibilityIdentifier("reader.study")
            }
            if showsCompanionToggle {
                Button("Study Panel", systemImage: "sidebar.right", action: onToggleCompanion)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
                .frame(width: width, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("reader.more")
    }

    private func iconButton(_ systemImage: String, label: String, width: CGFloat = 36, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: width, height: 36)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
