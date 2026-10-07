import SwiftData
import SwiftUI

/// Flashcards: the reference on the front; try to say the passage, peek at
/// the first letters if you need to, then turn the card and say how it went.
/// Cards marked "Again" come back at the end of the session.
struct MemoryReviewView: View {
    let session: MemorySession

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PracticeStreak.storageKey) private var streak = PracticeStreak()

    @State private var queue: [UUID] = []
    @State private var reviewed = 0
    @State private var revealed = false
    /// Opening words shown as a hint (0: none).
    @State private var hintWords = 0
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let id = queue.first, let verse = card(id) {
                    ProgressView(value: Double(reviewed), total: Double(reviewed + queue.count))
                        .tint(palette.accent)
                        .accessibilityLabel("Progress")
                        .accessibilityValue("\(reviewed) of \(reviewed + queue.count)")
                    cardView(verse)
                        .id(id)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    controls(verse)
                } else if started {
                    finished
                }
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedScreen()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("memorise.close")
                }
            }
            .onAppear {
                guard !started else { return }
                queue = session.cards.filter { card($0) != nil }
                started = true
            }
            .sensoryFeedback(.impact(weight: .light), trigger: revealed) { _, now in now }
        }
    }

    // MARK: Card

    private func cardView(_ verse: MemoryVerse) -> some View {
        let text = passageText(verse)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verse.reference.description)
                    .font(settings.preferences.font.font(size: 26, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("memorise.card.reference")
                Spacer()
                Text(translation(for: verse).abbreviation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }

            ScrollView {
                Group {
                    if revealed {
                        Text(text)
                            .font(settings.preferences.font.font(size: 21))
                            .foregroundStyle(palette.text)
                            .lineSpacing(6)
                            .accessibilityIdentifier("memorise.card.text")
                    } else if hintWords > 0 {
                        Text(MemoryHint.opening(text, words: hintWords))
                            .font(settings.preferences.font.font(size: 21))
                            .foregroundStyle(palette.text)
                            .lineSpacing(6)
                            .accessibilityIdentifier("memorise.card.hint")
                    } else {
                        Text("Say the passage to yourself, then turn the card.")
                            .font(.body)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if !revealed { reveal() } }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(_ verse: MemoryVerse) -> some View {
        if revealed {
            VStack(spacing: 10) {
                Text("How did you do?")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                HStack(spacing: 10) {
                    ForEach(MemoryGrade.allCases) { grade in
                        Button {
                            record(grade, for: verse)
                        } label: {
                            Text(grade.title)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(grade == .again ? .orange : palette.accent)
                        .accessibilityIdentifier("memorise.grade.\(grade.rawValue)")
                    }
                }
            }
        } else {
            let text = passageText(verse)
            HStack(spacing: 12) {
                Button {
                    // A few more words each time; the last step shows it all.
                    withAnimation { hintWords += MemoryHint.wordsPerStep }
                    if MemoryHint.isComplete(text, words: hintWords) { reveal() }
                } label: {
                    Label(hintWords == 0 ? String(localized: "Hint", comment: "Memorise: show the opening words") : String(localized: "More Words", comment: "Memorise: show a few more words of the verse"), systemImage: "lightbulb")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.hint")
                Button {
                    reveal()
                } label: {
                    Label("Show Verse", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.reveal")
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(palette.accent)
            Text("Well done")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.text)
            Text(reviewed == 1 ? String(localized: "You reviewed 1 verse.") : String(localized: "You reviewed \(reviewed) verses."))
                .foregroundStyle(palette.secondaryText)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.done")
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Actions

    private func reveal() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { revealed = true }
    }

    private func record(_ grade: MemoryGrade, for verse: MemoryVerse) {
        StudyStore(context: modelContext).review(verse, grade)
        // A review is practice too: it keeps the days-in-a-row streak going.
        streak = streak.recording(on: .now)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            let id = queue.removeFirst()
            if grade == .again { queue.append(id) } else { reviewed += 1 }
            revealed = false
            hintWords = 0
        }
    }

    // MARK: Data

    private func card(_ id: UUID) -> MemoryVerse? {
        let key = id
        var descriptor = FetchDescriptor<MemoryVerse>(predicate: #Predicate { $0.id == key })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func translation(for verse: MemoryVerse) -> Translation {
        library.translations.first { $0.id == verse.translationID } ?? library.currentTranslation
    }

    /// Verbatim from the Bible database.
    private func passageText(_ verse: MemoryVerse) -> String {
        let repository = library.repository(for: translation(for: verse))
        let verses = (try? repository.verses(from: verse.start, through: verse.end)) ?? []
        return verses.map(\.plainText).joined(separator: " ")
    }
}
