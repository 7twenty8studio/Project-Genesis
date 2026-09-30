import SwiftUI

/// The study assistant as a sheet, for a passage chosen in the reader.
struct StudyAssistantView: View {
    let passage: StudyPassage
    var initialAction: StudyAction = .explain
    /// False when opened for a whole chapter by a free account, so an answer
    /// is only fetched (and counted) when asked for.
    var autoLoads = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                StudyAssistantContent(passage: passage, initialAction: initialAction, autoLoads: autoLoads, onLeave: { dismiss() })
                    .padding(20)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle(passage.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("study.done")
                }
            }
        }
    }
}

/// The study assistant for a passage: the Scripture (from the local database)
/// and, separately and clearly labelled, AI-generated study notes. Used in the
/// sheet and, beside the text, in the study panel on wide screens.
struct StudyAssistantContent: View {
    let passage: StudyPassage
    /// False in the study panel, where the text is already beside it.
    var showsScripture = true
    /// Called before following a link that leaves this view (e.g. to close a sheet).
    var onLeave: () -> Void = {}
    /// False in the study panel: notes are fetched only when asked for, so
    /// turning pages doesn't use up a free account's daily answers.
    var autoLoads = true

    @Environment(StudyAssistant.self) private var assistant
    @Environment(EntitlementService.self) private var entitlements
    @Environment(BibleLibrary.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    @State private var action: StudyAction
    @State private var answer: StudyAnswer?
    @State private var error: StudyAssistantError?
    @State private var isLoading = false
    @State private var showsFullPassage = false
    @State private var premium: PremiumFeature?
    @State private var showsAccount = false
    @State private var requested: TaskKey?

    init(passage: StudyPassage, initialAction: StudyAction = .explain, showsScripture: Bool = true, autoLoads: Bool = true, onLeave: @escaping () -> Void = {}) {
        self.passage = passage
        self.showsScripture = showsScripture
        self.autoLoads = autoLoads
        self.onLeave = onLeave
        _action = State(initialValue: initialAction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsScripture { scripture }
            actions
            answerSection
        }
        .environment(\.openURL, OpenURLAction { url in
            // Answers may only link within the app.
            guard url.scheme == GenesisLink.scheme else { return .discarded }
            onLeave()
            router.handle(url)
            return .handled
        })
        .premiumSheet($premium)
        .sheet(isPresented: $showsAccount) { AccountView() }
        .task(id: TaskKey(passage: passage, action: action)) {
            // A free account opening a Premium tool starts with an explanation.
            guard assistant.canUse(action) else {
                action = .explain
                return
            }
            await load()
        }
    }

    private var key: TaskKey { TaskKey(passage: passage, action: action) }

    private struct TaskKey: Hashable {
        let passage: StudyPassage
        let action: StudyAction
    }

    // MARK: Scripture

    private var verses: [Verse] {
        (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
    }

    private var scripture: some View {
        let all = verses
        let shown = showsFullPassage ? all : Array(all.prefix(4))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scripture \u{00B7} \(library.currentTranslation.abbreviation)", systemImage: "book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button("Open") {
                    onLeave()
                    router.read(passage.start)
                }
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("study.openPassage")
            }
            Text(scriptureText(shown))
            .font(.system(.body, design: .serif))
            .foregroundStyle(palette.text)
            .lineSpacing(4)
            .accessibilityIdentifier("study.scripture")
            if all.count > shown.count {
                Button("Show all \(all.count) verses") { showsFullPassage = true }
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.separator))
    }

    /// Verse numbers small and in the accent colour, text verbatim.
    private func scriptureText(_ verses: [Verse]) -> AttributedString {
        var result = AttributedString()
        for verse in verses {
            var number = AttributedString("\(verse.id.verse) ")
            number.font = .caption.weight(.semibold)
            number.foregroundColor = palette.accent
            result += number
            result += AttributedString(verse.text + " ")
        }
        return result
    }

    // MARK: Actions

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudyAction.allCases) { item in
                    let locked = !assistant.canUse(item)
                    let isSelected = item == action
                    Button {
                        if locked {
                            premium = .advancedAI
                        } else {
                            action = item
                            requested = TaskKey(passage: passage, action: item)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.systemImage)
                            Text(item.title)
                            if locked { Image(systemName: "lock.fill").font(.caption2) }
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? palette.background : palette.text)
                        .background(isSelected ? palette.accent : palette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(locked ? "\(item.title), Premium" : item.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("study.action.\(item.rawValue)")
                }
            }
        }
    }

    // MARK: Answer

    @ViewBuilder
    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("AI-generated study notes \u{00B7} not Scripture")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.accent)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("study.aiLabel")

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing study notes\u{2026}")
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 8)
            } else if let answer {
                Text(StudyText.attributed(answer.content))
                    .font(.body)
                    .foregroundStyle(palette.text)
                    .tint(palette.accent)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .accessibilityIdentifier("study.answer")
            } else if let error {
                errorView(error)
            } else {
                Button {
                    requested = key
                    Task { await load() }
                } label: {
                    Label("\(action.title) \(passage.title)", systemImage: action.systemImage)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("study.request")
            }

            Text("AI can make mistakes. Weigh these notes against Scripture itself. Explanations aim to be non-denominational and note where Christian traditions differ.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            if !entitlements.isPremium, let used = assistant.usedToday, let limit = assistant.dailyLimit {
                Text("\(min(used, limit)) of \(limit) free explanations used today")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("study.usage")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func errorView(_ error: StudyAssistantError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(error.localizedDescription)
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("study.error")
            switch error {
            case .signInRequired:
                Button("Sign In or Create Account") { showsAccount = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("study.signIn")
            case .premiumRequired, .dailyLimit:
                Button("See Premium") { premium = .advancedAI }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("study.premium")
            case .offline, .server:
                Button("Try Again") { Task { await load() } }
            case .notConfigured:
                EmptyView()
            }
        }
    }

    private func load() async {
        answer = assistant.savedAnswer(action, passage: passage)
        error = nil
        guard answer == nil, autoLoads || requested == key else { return }
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await assistant.answer(action, passage: passage)
            guard !Task.isCancelled else { return }
            answer = result
        } catch let failure as StudyAssistantError {
            guard !Task.isCancelled else { return }
            error = failure
        } catch {
            // Switching tools cancels the previous request; that isn't an error.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = .server(error.localizedDescription)
        }
    }
}

/// Turns the assistant's text into styled text: **bold**, and verse
/// references written as [[John 3:16]] become links that open the reader.
enum StudyText {
    static func linked(_ content: String) -> String {
        // Drop any Markdown link the text already has: only verse links are made here.
        let plain = content.replacing(/\[([^\]\[]+)\]\([^)]*\)/) { String($0.output.1) }
        var result = ""
        var rest = Substring(plain)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            result += rest[..<open.lowerBound]
            let reference = String(rest[open.upperBound..<close.lowerBound])
            if let parsed = ReferenceParser.parse(reference) {
                result += "[\(reference)](\(GenesisLink.scheme)://read/\(parsed.firstVerse.rawValue))"
            } else {
                result += reference
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    static func attributed(_ content: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linked(content), options: options)) ?? AttributedString(content)
    }
}
