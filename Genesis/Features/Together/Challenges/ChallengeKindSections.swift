import SwiftData
import SwiftUI

/// Read together: your progress and each chapter to tick.
struct ReadingChallengeSections: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge

    @Environment(\.palette) private var palette

    var body: some View {
        let summary = model.summary(for: challenge)
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: summary.myFraction)
                    .tint(palette.accent)
                    .accessibilityHidden(true)
                Text(ChallengeText.rowProgress(challenge, summary: summary))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("challenge.myProgress")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Your Progress")
        }
        Section {
            ForEach(challenge.chapterIDs, id: \.self) { chapter in
                ReadingChallengeChapterRow(model: model, challenge: challenge, chapter: chapter)
            }
        } header: {
            Text("Chapters")
        } footer: {
            Text("Tick each chapter when you've read it.")
        }
    }
}

private struct ReadingChallengeChapterRow: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge
    let chapter: ChapterID

    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        let item = ReadingChallengeChapters.raw(chapter)
        let ticked = model.hasTicked(item, in: challenge)
        let name = chapter.description(in: library.currentTranslation.language)
        HStack(spacing: 12) {
            Button {
                Task { await model.setDone(!ticked, item: item, in: challenge) }
            } label: {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(ticked ? palette.accent : palette.separator)
            }
            .buttonStyle(.plain)
            .disabled(!model.canTick(item, in: challenge))
            .accessibilityLabel(name)
            .accessibilityValue(ticked ? "Read" : "Not read")
            .accessibilityIdentifier("challenge.chapter")
            Text(name)
                .foregroundStyle(palette.text)
                .strikethrough(ticked, color: palette.secondaryText)
                .accessibilityHidden(true)
            Spacer()
            Button("Read") { router.read(chapter) }
                .buttonStyle(.borderless)
                .font(.subheadline)
        }
    }
}

/// Memorise together: the passage (verbatim from your Bible), "I've learned
/// it", and Memorise's flashcards and games (Premium).
struct MemoriseChallengeSections: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge

    @Environment(BibleLibrary.self) private var library
    @Environment(FeaturePreferences.self) private var features
    @Environment(\.palette) private var palette

    /// The passage's words, exactly as the current Bible has them.
    private var passageText: String? {
        guard let start = challenge.passageStart, let end = challenge.passageEnd else { return nil }
        let verses = (try? library.current.verses(from: start, through: end)) ?? []
        return verses.isEmpty ? nil : verses.map(\.plainText).joined(separator: " ")
    }

    var body: some View {
        let text = passageText
        Section {
            passage(text)
        } header: {
            Text("The Passage")
        }
        Section {
            learnedButton
        } footer: {
            Text("Tick it when you can say it from memory.")
        }
        // Memorise lives with Plans & Prayer.
        if features.isOn(.plansAndPrayer), text != nil {
            Section {
                MemoriseChallengePractice(challenge: challenge)
            } header: {
                Text("Practise")
            }
        }
    }

    private func passage(_ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(challenge.passage?.description(in: library.currentTranslation.language) ?? "")
                .font(.headline)
                .foregroundStyle(palette.text)
            if let text {
                Text(text)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(palette.text)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("challenge.passage")
                Text(library.currentTranslation.abbreviation)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("This passage isn't in the Bible you're reading.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var learnedButton: some View {
        let learned = model.hasTicked(GroupChallenge.learnedItem, in: challenge)
        return Button {
            Task { await model.setDone(!learned, item: GroupChallenge.learnedItem, in: challenge) }
        } label: {
            Label(learned ? "I've Learned It" : "Mark as Learned", systemImage: learned ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(.borderless)
        .disabled(!model.canTick(GroupChallenge.learnedItem, in: challenge))
        .accessibilityIdentifier("challenge.learned")
    }
}

/// Add the passage to Memorise and play a game with it (Premium), or a
/// teaser for free accounts.
private struct MemoriseChallengePractice: View {
    let challenge: GroupChallenge

    @Environment(BibleLibrary.self) private var library
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \MemoryVerse.dueAt) private var verses: [MemoryVerse]
    @State private var game: MemoryGameSession?

    private var isInMemorise: Bool {
        verses.contains { $0.startRaw == challenge.verseStart && $0.endRaw == (challenge.verseEnd ?? challenge.verseStart) }
    }

    var body: some View {
        if entitlements.allows(.memorise) {
            Button {
                _ = addToMemorise()
            } label: {
                Label(isInMemorise ? "In Your Memorise List" : "Add to Memorise", systemImage: isInMemorise ? "checkmark" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(isInMemorise)
            .accessibilityIdentifier("challenge.addToMemorise")
            Menu {
                ForEach(MemoryGameMode.allCases) { mode in
                    Button {
                        play(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            } label: {
                Label("Play a Game", systemImage: "gamecontroller")
            }
            .accessibilityIdentifier("challenge.play")
            .fullScreenCover(item: $game) { session in
                if session.mode == .speed {
                    SpeedRoundView(session: session)
                } else {
                    MemoryGameView(session: session)
                }
            }
        } else {
            PremiumTeaser(message: String(localized: "Practise this passage with Memorise's flashcards and games, part of Premium."), feature: .memorise)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    /// Adds the passage in the Bible you're reading (or finds it there).
    private func addToMemorise() -> MemoryVerse? {
        guard let start = challenge.passageStart, let end = challenge.passageEnd else { return nil }
        return StudyStore(context: modelContext).memorise(from: start, through: end, translationID: library.currentTranslation.id)
    }

    private func play(_ mode: MemoryGameMode) {
        guard let verse = addToMemorise() else { return }
        // Results move the review schedule only when the passage is due.
        game = MemoryGameSession(mode: mode, cards: [verse.id], isPractice: !verse.isDue())
    }
}

/// Streak and prayer challenges: today's tick, your streak, who's still
/// going, and every day so far.
struct DailyChallengeSections: View {
    let model: GroupChallengesModel
    let groupModel: GroupDetailModel
    let challenge: GroupChallenge

    @Environment(\.palette) private var palette

    var body: some View {
        let summary = model.summary(for: challenge)
        Section {
            today(summary)
            streakLine(summary)
            Text(ChallengeText.stillGoing(summary))
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier("challenge.stillGoing")
        } header: {
            Text("Today")
        }
        Section {
            ChallengeDayGrid(model: model, challenge: challenge, ticked: summary.myItems)
        } header: {
            Text("Every Day")
        }
        if challenge.kind == .prayer {
            Section {
                NavigationLink {
                    GroupPrayersView(model: groupModel)
                        .themedScreen()
                        .navigationTitle("Prayer Requests")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("The Group's Prayer Requests", systemImage: "hands.and.sparkles")
                        .foregroundStyle(palette.accent)
                }
                .accessibilityIdentifier("challenge.prayers")
            }
        }
    }

    @ViewBuilder
    private func today(_ summary: GroupChallengeSummary) -> some View {
        switch model.status(of: challenge) {
        case .running:
            let day = model.today(in: challenge)
            let done = summary.myItems.contains(day)
            Button {
                Task { await model.setDone(!done, item: day, in: challenge) }
            } label: {
                Label(Self.todayTitle(challenge.kind, done: done), systemImage: done ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("challenge.today")
        case .upcoming:
            Text("You can tick each day once the challenge begins.")
                .foregroundStyle(palette.secondaryText)
        case .finished:
            Text("This challenge has finished.")
                .foregroundStyle(palette.secondaryText)
        }
    }

    private static func todayTitle(_ kind: GroupChallengeKind, done: Bool) -> String {
        switch (kind, done) {
        case (.prayer, true): String(localized: "Prayed today")
        case (.prayer, false): String(localized: "I prayed today")
        case (_, true): String(localized: "Read today")
        case (_, false): String(localized: "I read today")
        }
    }

    @ViewBuilder
    private func streakLine(_ summary: GroupChallengeSummary) -> some View {
        let count = summary.myStreak
        if count > 0 {
            Label(count == 1 ? String(localized: "1 day in a row") : String(localized: "\(count) days in a row"), systemImage: "flame")
                .font(.subheadline)
                .foregroundStyle(palette.text)
        }
    }
}

/// Every day of a daily challenge: ticked days filled, today ringed, days
/// ahead not yet tickable.
private struct ChallengeDayGrid: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge
    let ticked: Set<Int>

    @Environment(\.palette) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        let today = model.today(in: challenge)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...challenge.days, id: \.self) { day in
                dayButton(day, today: today)
            }
        }
        .padding(.vertical, 6)
    }

    private func dayButton(_ day: Int, today: Int) -> some View {
        let done = ticked.contains(day)
        let isToday = day == today
        return Button {
            Task { await model.setDone(!done, item: day, in: challenge) }
        } label: {
            Text(day, format: .number)
                .font(.caption.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(done ? palette.background : (day > today ? palette.secondaryText : palette.text))
                .frame(width: 34, height: 34)
                .background(Circle().fill(done ? palette.accent : Color.clear))
                .overlay(Circle().stroke(isToday ? palette.accent : palette.separator, lineWidth: isToday ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(day > today || !model.canTick(day, in: challenge))
        .accessibilityLabel("Day \(day)")
        .accessibilityValue(done ? "Done" : "Not done")
    }
}
