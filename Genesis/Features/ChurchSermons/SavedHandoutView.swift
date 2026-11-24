import SwiftData
import SwiftUI

/// The member's saved work on a church's handout, opened from their Sermon
/// Notes: the outline of the revision they filled in (it still opens after
/// the church unpublishes or changes the sermon) and their answers. It can
/// be checked only with the key saved for that revision.
struct SavedHandoutView: View {
    let handout: SermonHandout
    @Bindable var notes: Sermon

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @State private var model: HandoutModel?
    @State private var passage: StudyRange?
    /// The Bible picked for every passage of this handout.
    @State private var passageBible: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(handout.church)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.accent)
                Text(handout.title.isEmpty ? String(localized: "Sermon") : handout.title)
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Saved \(handout.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                ForEach(handout.outline) { block in
                    blockView(block)
                }
                HandoutBar()
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .environment(model)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .navigationTitle("Your Handout")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: handout.id) { start() }
        .sheet(item: Binding(get: { passage.map(PassageItem.init) }, set: { passage = $0?.range })) { item in
            ChurchPassageSheet(range: item.range, quoted: nil, choice: $passageBible) { verse in
                passage = nil
                router.read(verse)
            }
        }
    }

    private struct PassageItem: Identifiable {
        let range: StudyRange
        var id: String { "\(range.start.rawValue)-\(range.end.rawValue)" }
    }

    @ViewBuilder
    private func blockView(_ block: SermonBlock) -> some View {
        switch block {
        case let .heading(_, text, level):
            HandoutText(text: text, font: .system(level == 1 ? .title2 : .title3, design: .serif, weight: .semibold))
                .padding(.top, 8)
        case let .paragraph(_, text):
            HandoutText(text: text, font: .system(.body, design: .serif))
        case let .quote(_, text):
            Text(text)
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(palette.text)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.accent.opacity(0.5)).frame(width: 3)
                }
                .fixedSize(horizontal: false, vertical: true)
        case let .list(_, items, ordered):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "\u{2022}")
                            .foregroundStyle(palette.secondaryText)
                        HandoutText(text: item, font: .system(.body, design: .serif))
                    }
                }
            }
        case let .scripture(_, reference):
            ChurchSermonReferenceRow(reference: reference, language: library.currentTranslation.language, shown: library.churchPassageBible(chosen: passageBible)) { range in
                passage = range
            }
        }
    }

    private func start() {
        let handout = handout
        let notes = notes
        let context = modelContext
        model = HandoutModel(
            blanks: handout.blanks,
            answers: handout.hasKey ? .revealed : .hidden,
            responses: HandoutModel.read(handout.responses)
        ) { responses in
            ChurchSermonNotes.update(handout, responses: HandoutModel.stored(responses), in: notes, context: context)
        }
    }
}

/// Sermon Notes' list of the church handouts the person filled in.
struct SermonHandoutsSection: View {
    @Bindable var sermon: Sermon

    var body: some View {
        let handouts = sermon.handouts
        if !handouts.isEmpty {
            Section {
                ForEach(handouts.reversed()) { handout in
                    NavigationLink {
                        SavedHandoutView(handout: handout, notes: sermon)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(handout.title.isEmpty ? String(localized: "Your Handout") : handout.title)
                            Text(handout.hasKey ? String(localized: "Saved \(handout.savedAt.formatted(date: .abbreviated, time: .omitted)) · Answers saved") : String(localized: "Saved \(handout.savedAt.formatted(date: .abbreviated, time: .omitted))"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("sermon.handout")
                }
            } header: {
                Text("Your Handout")
            } footer: {
                Text("Your answers on the church's handout. They're private, and they stay even if the church changes or removes the sermon.")
            }
        }
    }
}
