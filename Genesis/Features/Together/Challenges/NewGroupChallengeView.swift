import SwiftUI

/// Owners and moderators start a challenge: what kind, a title (suggested),
/// when and how long, and what to read or learn.
struct NewGroupChallengeView: View {
    let model: GroupChallengesModel

    @Environment(BibleLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var kind: GroupChallengeKind = .reading
    @State private var title = ""
    /// Once the leader types a title, suggestions stop replacing it.
    @State private var titleEdited = false
    @State private var details = ""
    @State private var startsOn = Date.now
    @State private var days = GroupChallengeKind.reading.defaultDays
    @State private var reading = ReadingChallengeSelection()
    @State private var passageText = ""
    @State private var isSaving = false

    private var passage: (start: VerseID, end: VerseID)? { ChallengePassage.parse(passageText) }

    private var passageReference: PassageReference? {
        passage.flatMap { PassageReference(verses: [$0.start, $0.end]) }
    }

    /// The passage is in the Bible being read (so everyone sees real words).
    private var passageIsInBible: Bool {
        guard let passage else { return false }
        return ((try? library.current.verses(from: passage.start, through: passage.end)) ?? []).isEmpty == false
    }

    private var suggestedTitle: String {
        switch kind {
        case .reading: ChallengeTitleSuggestion.reading(reading, days: days)
        case .memorise: ChallengeTitleSuggestion.memorise(passageReference)
        case .streak: ChallengeTitleSuggestion.streak(days: days)
        case .prayer: ChallengeTitleSuggestion.prayer(days: days)
        }
    }

    private var draft: GroupChallengeDraft {
        GroupChallengeDraft(
            kind: kind, title: title, details: details, startsOn: startsOn, days: days,
            chapters: kind == .reading ? reading.chapters : [],
            verseStart: kind == .memorise ? passage?.start : nil,
            verseEnd: kind == .memorise ? passage?.end : nil,
            translationID: kind == .memorise ? library.currentTranslation.id : nil
        )
    }

    private var canStart: Bool {
        draft.isValid() && (kind != .memorise || passageIsInBible) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                ThemedRows {
                    kindSection
                    aboutSection
                    whenSection
                    switch kind {
                    case .reading:
                        ChallengeReadingPicker(selection: $reading)
                    case .memorise:
                        ChallengePassagePicker(text: $passageText)
                    case .streak, .prayer:
                        EmptyView()
                    }
                    if let error = model.errorMessage {
                        Section {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", systemImage: "checkmark") { save() }
                        .disabled(!canStart)
                        .accessibilityIdentifier("newChallenge.start")
                }
            }
            .onAppear {
                if title.isEmpty { title = suggestedTitle }
            }
            .onChange(of: kind) { _, newKind in
                days = newKind.defaultDays
            }
            .onChange(of: suggestedTitle) { _, suggestion in
                if !titleEdited { title = suggestion }
            }
        }
    }

    private func save() {
        isSaving = true
        let draft = self.draft
        Task {
            if await model.create(draft) != nil { dismiss() }
            isSaving = false
        }
    }

    // MARK: Sections

    private var kindSection: some View {
        Section {
            ForEach(GroupChallengeKind.allCases) { option in
                Button {
                    kind = option
                } label: {
                    ChallengeKindOption(kind: option, isSelected: kind == option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? .isSelected : [])
                .accessibilityIdentifier("newChallenge.kind.\(option.rawValue)")
            }
        } header: {
            Text("Kind of Challenge")
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { title },
            set: { newValue in
                title = newValue
                titleEdited = !newValue.isEmpty
            }
        )
    }

    private var aboutSection: some View {
        Section {
            TextField("Title", text: titleBinding)
                .accessibilityIdentifier("newChallenge.title")
            TextField("Details (optional)", text: $details, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier("newChallenge.details")
        } header: {
            Text("About")
        }
    }

    private var startRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let latest = Calendar.current.date(byAdding: .day, value: GroupChallengeRules.latestStartDays, to: today) ?? today
        return today...latest
    }

    private var whenSection: some View {
        Section {
            DatePicker("Starts", selection: $startsOn, in: startRange, displayedComponents: .date)
            Stepper(value: $days, in: GroupChallengeRules.dayRange) {
                Text(days == 1 ? "1 day" : "\(days) days")
            }
            .accessibilityIdentifier("newChallenge.days")
            Picker("Length", selection: $days) {
                ForEach(kind.suggestedDays, id: \.self) { count in
                    Text("\(count) days").tag(count)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("When")
        } footer: {
            Text(endsLine)
        }
    }

    private var endsLine: String {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: startsOn) ?? startsOn
        let date = end.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Ends \(date).")
    }
}

/// A kind of challenge with its one-line description.
private struct ChallengeKindOption: View {
    let kind: GroupChallengeKind
    let isSelected: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .foregroundStyle(palette.text)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
