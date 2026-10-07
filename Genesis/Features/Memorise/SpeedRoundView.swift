import SwiftData
import SwiftUI

/// Speed Round: one minute to recall as many passages as you can. Say each
/// one to yourself, show it, and mark it honestly; "I knew it" counts as a
/// good review and "Not yet" brings it back soon (`MemoryGame.speedGrade`).
struct SpeedRoundView: View {
    let session: MemoryGameSession

    nonisolated static let duration = 60

    private enum Phase { case ready, playing, finished }

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PracticeStreak.storageKey) private var streak = PracticeStreak()

    @State private var phase = Phase.ready
    @State private var queue: [UUID] = []
    @State private var remaining = SpeedRoundView.duration
    @State private var revealed = false
    @State private var knownCount = 0
    @State private var gradedCount = 0

    private var source: MemoryPassageSource { MemoryPassageSource(library: library, context: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch phase {
                case .ready:
                    ready
                case .playing:
                    if let id = queue.first, let verse = source.card(id) {
                        clock
                        card(verse)
                            .id(id)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                        controls(verse)
                    }
                case .finished:
                    MemoryGameFinished(count: gradedCount, detail: tally) { dismiss() }
                }
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedScreen()
            .navigationTitle(MemoryGameMode.speed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("memorise.close")
                }
            }
            .onAppear {
                if queue.isEmpty { queue = session.cards.filter { source.card($0) != nil } }
            }
            .task(id: phase) {
                guard phase == .playing else { return }
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    remaining -= 1
                }
                withAnimation { phase = .finished }
            }
            .sensoryFeedback(.success, trigger: knownCount) { old, new in new > old }
        }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("One minute")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.text)
            Text("Say each verse to yourself, then show it and mark how you did.")
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                withAnimation { phase = queue.isEmpty ? .finished : .playing }
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .accessibilityIdentifier("memorise.speed.start")
        }
        .frame(maxHeight: .infinity)
    }

    private var clock: some View {
        HStack {
            Image(systemName: "timer")
                .accessibilityHidden(true)
            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
                .accessibilityIdentifier("memorise.speed.clock")
            Spacer()
            ProgressView(value: Double(remaining), total: Double(Self.duration))
                .tint(palette.accent)
                .frame(maxWidth: 160)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.secondaryText)
    }

    private func card(_ verse: MemoryVerse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verse.reference.description(in: source.translation(for: verse).language))
                .font(settings.preferences.font.font(size: 26, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("memorise.speed.reference")
            ScrollView {
                if revealed {
                    // Verbatim from the Bible database.
                    SolvedPassage(text: source.passageText(verse))
                } else {
                    Text("Say the passage to yourself, then show it.")
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if !revealed { reveal() } }
    }

    @ViewBuilder
    private func controls(_ verse: MemoryVerse) -> some View {
        if revealed {
            HStack(spacing: 10) {
                Button {
                    mark(verse, knewIt: false)
                } label: {
                    Text("Not yet")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(palette.secondaryText)
                .accessibilityIdentifier("memorise.speed.notYet")
                Button {
                    mark(verse, knewIt: true)
                } label: {
                    Text("I knew it")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("memorise.speed.knew")
            }
        } else {
            Button {
                reveal()
            } label: {
                Label("Show Verse", systemImage: "eye")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .accessibilityIdentifier("memorise.speed.reveal")
        }
    }

    private var tally: String {
        String(localized: "You knew \(knownCount) of \(gradedCount) verses.")
    }

    private func reveal() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { revealed = true }
    }

    private func mark(_ verse: MemoryVerse, knewIt: Bool) {
        StudyStore(context: modelContext).recordGame(verse, MemoryGame.speedGrade(knewIt: knewIt))
        streak = streak.recording(on: .now)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            gradedCount += 1
            if knewIt { knownCount += 1 }
            revealed = false
            queue.removeFirst()
            // Each passage comes up once; the round ends early when all are done.
            if queue.isEmpty { phase = .finished }
        }
    }
}
