import SwiftData
import SwiftUI

/// Fill the Gaps or Word Order over a set of passages, one at a time. When a
/// passage is solved it shows in full, verbatim, and the result goes to the
/// review schedule (if it was due) and the practice streak.
struct MemoryGameView: View {
    let session: MemoryGameSession

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PracticeStreak.storageKey) private var streak = PracticeStreak()

    @State private var queue: [UUID] = []
    @State private var started = false
    /// Passages finished and moved past.
    @State private var completed = 0
    /// Passages solved (drives the success haptic as each one is done).
    @State private var solvedCount = 0
    /// The passage just solved, shown in full before moving on.
    @State private var solvedText: String?

    private var source: MemoryPassageSource { MemoryPassageSource(library: library, context: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let id = queue.first, let verse = source.card(id) {
                    ProgressView(value: Double(completed), total: Double(completed + queue.count))
                        .tint(palette.accent)
                        .accessibilityLabel("Progress")
                        .accessibilityValue("\(completed) of \(completed + queue.count)")
                    board(verse)
                        .id(id)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                } else if started {
                    MemoryGameFinished(count: completed) { dismiss() }
                }
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedScreen()
            .navigationTitle(session.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("memorise.close")
                }
            }
            .onAppear {
                guard !started else { return }
                queue = session.cards.filter { id in
                    guard let verse = source.card(id) else { return false }
                    return !source.passageText(verse).isEmpty
                }
                started = true
            }
            .sensoryFeedback(.success, trigger: solvedCount) { old, new in new > old }
        }
    }

    private func board(_ verse: MemoryVerse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verse.reference.description(in: source.translation(for: verse).language))
                    .font(settings.preferences.font.font(size: 24, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("memorise.game.reference")
                Spacer()
                Text(source.translation(for: verse).abbreviation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }

            if let solvedText {
                ScrollView { SolvedPassage(text: solvedText) }
                    .frame(maxHeight: .infinity)
                Button {
                    next()
                } label: {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.game.next")
            } else {
                switch session.mode {
                case .fillGaps:
                    FillGapsBoard(text: source.passageText(verse), mastery: verse.mastery, nearby: source.nearbyTexts(verse)) { mistakes, steps in
                        solved(verse, mistakes: mistakes, steps: steps)
                    }
                case .wordOrder:
                    WordOrderBoard(verseTexts: source.verseTexts(verse)) { mistakes, steps in
                        solved(verse, mistakes: mistakes, steps: steps)
                    }
                case .speed:
                    // Speed Round has its own screen (SpeedRoundView).
                    EmptyView()
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.separator, lineWidth: 1))
    }

    private func solved(_ verse: MemoryVerse, mistakes: Int, steps: Int) {
        // A clean game counts as a good review; see MemoryGame.grade.
        StudyStore(context: modelContext).recordGame(verse, MemoryGame.grade(mistakes: mistakes, steps: steps))
        streak = streak.recording(on: .now)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            // Always the passage verbatim from the database.
            solvedText = source.passageText(verse)
            solvedCount += 1
        }
    }

    private func next() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            solvedText = nil
            if !queue.isEmpty {
                queue.removeFirst()
                completed += 1
            }
        }
    }
}

/// The end of a game: how many passages were practised.
struct MemoryGameFinished: View {
    let count: Int
    /// An extra line, such as Speed Round's tally.
    var detail: String?
    let onDone: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Well done")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.text)
            Text(count == 1 ? String(localized: "You practised 1 verse.") : String(localized: "You practised \(count) verses."))
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("memorise.game.tally")
            }
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.done")
        }
        .frame(maxHeight: .infinity)
    }
}
