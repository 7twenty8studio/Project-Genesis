import SwiftUI

/// Floating controls shown when the reader is tapped: chapter navigation,
/// translation, bookmark and reading settings.
struct ReaderControls: View {
    let showsCompanionToggle: Bool
    let onChapterPicker: () -> Void
    let onSettings: () -> Void
    let onToggleCompanion: () -> Void

    @Environment(ReaderViewModel.self) private var reader
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                iconButton("chevron.left", label: "Previous chapter", enabled: reader.chapterID.previous != nil) {
                    reader.goToPreviousChapter()
                }
                Button(action: onChapterPicker) {
                    Text(reader.chapterID.description)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                }
                .accessibilityHint("Choose a book and chapter")
                iconButton("chevron.right", label: "Next chapter", enabled: reader.chapterID.next != nil) {
                    reader.goToNextChapter()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Menu {
                    Picker("Translation", selection: translationBinding) {
                        ForEach(library.translations) { translation in
                            Text("\(translation.abbreviation) · \(translation.name)").tag(translation)
                        }
                    }
                } label: {
                    Text(reader.translation.abbreviation)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 40, minHeight: 36)
                }
                .accessibilityLabel("Translation, \(reader.translation.name)")

                let bookmarked = reader.isCurrentChapterBookmarked
                iconButton(bookmarked ? "bookmark.fill" : "bookmark", label: bookmarked ? "Remove bookmark" : "Add bookmark") {
                    reader.toggleBookmark()
                }
                .sensoryFeedback(.selection, trigger: bookmarked)

                iconButton("textformat.size", label: "Reading settings", action: onSettings)

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

    private var translationBinding: Binding<Translation> {
        Binding(
            get: { reader.translation },
            set: { reader.switchTranslation(to: $0) }
        )
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
