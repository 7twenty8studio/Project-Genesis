import SwiftUI

/// Floating controls shown when the reader is tapped: chapter navigation,
/// translation, bookmark and reading settings.
struct ReaderControls: View {
    let showsCompanionToggle: Bool
    let onChapterPicker: () -> Void
    let onSettings: () -> Void
    let onStudy: () -> Void
    let onToggleCompanion: () -> Void

    @Environment(ReaderViewModel.self) private var reader
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(StudyAssistant.self) private var assistant

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                iconButton("chevron.left", label: "Previous chapter", enabled: reader.chapterID.previous != nil) {
                    reader.goToPreviousChapter()
                }
                .accessibilityIdentifier("reader.previousChapter")
                Button(action: onChapterPicker) {
                    Text(reader.chapterID.description)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                }
                .accessibilityHint("Choose a book and chapter")
                .accessibilityIdentifier("reader.chapterButton")
                iconButton("chevron.right", label: "Next chapter", enabled: reader.chapterID.next != nil) {
                    reader.goToNextChapter()
                }
                .accessibilityIdentifier("reader.nextChapter")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 2) {
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
                } label: {
                    Text(reader.translation.abbreviation)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 40, minHeight: 36)
                }
                .accessibilityLabel("Translation, \(reader.translation.name)")
                .accessibilityIdentifier("reader.translation")

                let bookmarked = reader.isCurrentChapterBookmarked
                iconButton(bookmarked ? "bookmark.fill" : "bookmark", label: bookmarked ? "Remove bookmark" : "Add bookmark") {
                    reader.toggleBookmark()
                }
                .sensoryFeedback(.selection, trigger: bookmarked)
                .accessibilityIdentifier("reader.bookmark")

                if assistant.isEnabled {
                    iconButton("sparkles", label: "Study this chapter", action: onStudy)
                        .accessibilityIdentifier("reader.study")
                }

                iconButton("textformat.size", label: "Reading settings", action: onSettings)
                    .accessibilityIdentifier("reader.settings")

                if showsCompanionToggle {
                    iconButton("sidebar.right", label: "Toggle study panel", action: onToggleCompanion)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 16)
    }

    private func iconButton(_ systemImage: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
