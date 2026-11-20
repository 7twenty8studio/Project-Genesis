import SwiftUI

/// About Matthew Henry's Concise Commentary (the word study's Commentary
/// tab): who wrote it and when, that it reflects his historical context and
/// theological views, and which edition Versely shows (the Concise
/// Commentary, an abridgment) with nothing left out.
/// The owner asked for this introduction on 19 November 2026, with the
/// passage-specific editorial notes paused
/// (Tools/StudyData/translations/commentary/NOTES.md).
struct CommentaryAboutSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section("Matthew Henry (1662–1714)") {
                        Text(Self.sentences[0...1].joined(separator: " "))
                            .foregroundStyle(palette.text)
                        Text(Self.sentences[2...3].joined(separator: " "))
                            .foregroundStyle(palette.text)
                        Text(Self.sentences[4...5].joined(separator: " "))
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .themedScreen()
            .navigationTitle("About This Commentary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("commentaryAbout.done")
                }
            }
        }
    }

    /// One sentence per string (the catalogs' rule), shown together.
    static let sentences = [
        String(localized: "Matthew Henry was an English Presbyterian minister."),
        String(localized: "His Exposition of the Old and New Testaments appeared in the early 1700s, and other ministers completed it from his notes after his death in 1714."),
        String(localized: "It reflects the historical context of his time and his own theological views."),
        String(localized: "Versely uses Matthew Henry's Concise Commentary on the Whole Bible, a later abridgment of that work, and shows this edition complete, with nothing left out."),
        String(localized: "A commentary is one writer's interpretation, not Scripture."),
        String(localized: "Read it alongside the Bible, not in place of it."),
    ]
}
