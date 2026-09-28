import SwiftData
import SwiftUI

/// A calm starting place: continue reading, today's verse, recent highlights
/// and notes, and the Bibles on this device.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(ReadingProgress.self) private var progress
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    @Query(HomeView.recentHighlightsQuery) private var recentHighlights: [Highlight]
    @Query(HomeView.recentNotesQuery) private var recentNotes: [Note]
    @State private var editingNote: Note?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    continueReading
                    dailyVerse
                    if !recentHighlights.isEmpty { highlights }
                    if !recentNotes.isEmpty { notes }
                    bibles
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingNote) { note in
                NavigationStack { NoteEditorView(note: note) }
            }
        }
    }

    // MARK: Sections

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Text(greetingText)
                .font(.system(.largeTitle, design: .serif, weight: .regular))
                .foregroundStyle(palette.text)
        }
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var continueReading: some View {
        let position = progress.position
        let verse = try? library.current.verse(position)
        return Button {
            router.continueReading()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(progress.hasStartedReading ? "Continue Reading" : "Begin Reading")
                        .font(.caption.weight(.semibold))
                        .kerning(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.accent)
                    Spacer()
                    Image(systemName: "book")
                        .foregroundStyle(palette.accent)
                }
                Text(position.chapterID.description)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let verse {
                    Text(verse.plainText)
                        .font(settings.preferences.font.font(size: 16))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                ProgressView(value: progress.progressThroughBook)
                    .tint(palette.accent)
                    .accessibilityLabel("Progress through \(position.chapterID.bibleBook.name)")
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var dailyVerse: some View {
        let id = DailyVerse.verse()
        let verse = try? library.current.verse(id)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Verse of the Day")
            Button {
                router.read(id)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verse?.plainText ?? "")
                        .font(settings.preferences.font.font(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    Text("\(PassageReference(verse: id).description) · \(library.currentTranslation.abbreviation)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [palette.surface, palette.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.accent.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let verse {
                    ShareLink(item: ChapterTextBuilder.shareText(for: [verse], translation: library.currentTranslation))
                }
            }
        }
    }

    private var highlights: some View {
        let texts = (try? library.current.verses(withIDs: recentHighlights.map(\.verse))) ?? [:]
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently Highlighted", action: ("See All", { router.tab = .library }))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recentHighlights) { highlight in
                        Button {
                            router.read(highlight.verse)
                        } label: {
                            VerseSnippet(
                                reference: PassageReference(verse: highlight.verse).description,
                                text: texts[highlight.verse]?.plainText ?? "",
                                highlight: highlight.color,
                                lineLimit: 4
                            )
                            .frame(width: 240, alignment: .topLeading)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent Notes", action: ("See All", { router.tab = .library }))
            VStack(spacing: 0) {
                ForEach(recentNotes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        NoteRow(note: note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if note.id != recentNotes.last?.id {
                        Divider().overlay(palette.separator)
                    }
                }
            }
            .card()
        }
    }

    private var bibles: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Bibles on This Device")
            VStack(spacing: 0) {
                ForEach(library.translations) { translation in
                    Button {
                        router.reader.switchTranslation(to: translation)
                    } label: {
                        HStack(spacing: 14) {
                            Text(translation.abbreviation)
                                .font(.system(.subheadline, design: .serif, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(translation.name)
                                    .foregroundStyle(palette.text)
                                Text(library.isAvailableOffline(translation) ? "Available offline" : "Not downloaded")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            if translation == library.currentTranslation {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                                    .accessibilityLabel("Current translation")
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    // MARK: Queries

    private static var recentHighlightsQuery: FetchDescriptor<Highlight> {
        var descriptor = FetchDescriptor<Highlight>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 10
        return descriptor
    }

    private static var recentNotesQuery: FetchDescriptor<Note> {
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 3
        return descriptor
    }
}
