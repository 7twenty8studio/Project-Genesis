import SwiftData
import SwiftUI
import UIKit

/// The heart of the app: distraction-free reading with controls that appear
/// on tap. On wide screens (iPad, iPhone Duo open) a companion panel sits
/// beside the text for notes, cross references and search.
struct ReaderView: View {
    @Environment(ReaderViewModel.self) private var reader
    @Environment(EntitlementService.self) private var entitlements
    @Environment(ReaderSettings.self) private var settings
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sheet: ReaderSheet?
    @State private var showsCompanion = true
    @State private var companionMode: CompanionPanel.Mode = .notes
    /// Read from the window once it exists; nil until then so text is laid
    /// out once with the right insets rather than twice.
    @State private var windowSafeArea: UIEdgeInsets?
    @FocusState private var isFocused: Bool

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var preferences: ReaderPreferences { settings.preferences }

    var body: some View {
        HStack(spacing: 0) {
            if isWide && showsCompanion && preferences.leftHanded {
                companion
                Divider()
            }
            readingSurface
            if isWide && showsCompanion && !preferences.leftHanded {
                Divider()
                companion
            }
        }
        .background(palette.background.ignoresSafeArea())
        .toolbarVisibility(reader.showsControls && !reader.isSelecting ? .visible : .hidden, for: .tabBar)
        .statusBarHidden(!reader.showsControls)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: reader.showsControls)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: reader.isSelecting)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            windowSafeArea = DeviceScreen.safeAreaInsets
            reader.modelContext = modelContext
            // Highlights or notes may have changed in the Library tab.
            reader.notesDidChange()
            isFocused = true
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .tracksReadingTime()
        .onKeyPress(.rightArrow) { turnPage(forward: true) }
        .onKeyPress(.leftArrow) { turnPage(forward: false) }
        .onKeyPress(.space) { turnPage(forward: true) }
        .onKeyPress(.escape) {
            reader.clearSelection()
            return .handled
        }
    }

    // MARK: Reading surface

    private var readingSurface: some View {
        GeometryReader { proxy in
            let layout = ReaderLayout(
                size: proxy.size,
                safeArea: readerSafeArea,
                style: ReaderStyle(
                    preferences: preferences,
                    theme: preferences.theme.resolved(for: colorScheme),
                    contentSizeCategory: UIContentSizeCategory(dynamicTypeSize)
                ),
                margins: preferences.margins
            )
            ZStack {
                palette.background
                if windowSafeArea != nil {
                    textView(layout: layout)
                        .accessibilityAction(named: "Next page") { _ = turnPage(forward: true) }
                        .accessibilityAction(named: "Previous page") { _ = turnPage(forward: false) }
                        .accessibilityAction(named: "Show controls") { reader.showsControls = true }
                }

                if reader.isSelecting {
                    SelectionActionBar(
                        onNote: openNoteForSelection,
                        onCrossReferences: showCrossReferencesForSelection,
                        onExplain: explainSelection
                    )
                    .padding(.bottom, readerSafeArea.bottom + 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        // The controls live in an overlay that respects the *live* safe area,
        // so they always clear the status bar, Dynamic Island and camera
        // cut-outs (the iPhone Duo's camera sits in a corner), whichever of
        // those is showing right now.
        .overlay {
            GeometryReader { overlay in
                if reader.showsControls && !reader.isSelecting {
                    ReaderControls(
                        showsCompanionToggle: isWide,
                        onChapterPicker: { sheet = .chapterPicker },
                        onSettings: { sheet = .settings },
                        onStudy: studyChapter,
                        onListen: listen,
                        onToggleCompanion: { showsCompanion.toggle() }
                    )
                    // At least a little below the live safe area, and never
                    // higher than the stable position (which on iPad clears
                    // the floating tab bar).
                    .padding(.top, max(4, readerSafeArea.top + controlsTopClearance - overlay.safeAreaInsets.top))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                }
                if audio.isActive && reader.showsControls && !reader.isSelecting {
                    AudioMiniPlayer { sheet = .audio }
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
            // Rotation changes which edges have insets.
            windowSafeArea = DeviceScreen.safeAreaInsets
        }
        .onChange(of: reader.showsControls) {
            // Some screens report a smaller top inset while the status bar is
            // hidden. If a larger one shows up, keep the text clear of it too
            // (grow only, so the page doesn't reflow every time controls toggle).
            let live = DeviceScreen.safeAreaInsets
            if let current = windowSafeArea, live.top > current.top {
                var grown = current
                grown.top = live.top
                windowSafeArea = grown
            }
        }
    }

    @ViewBuilder
    private func textView(layout: ReaderLayout) -> some View {
        if preferences.readingMode == .page {
            let turn: PageTurnStyle = reduceMotion ? .slide : preferences.pageTurn
            PagedReaderView(
                viewModel: reader,
                layout: layout,
                pageTurn: turn,
                leftHanded: preferences.leftHanded,
                navigationToken: reader.navigationToken,
                decorationsVersion: reader.decorationsVersion,
                translationID: reader.translation.id,
                pageTurnToken: reader.pageTurnToken
            )
            // The transition style can only be set when the controller is created.
            .id(turn)
        } else {
            ScrollReaderView(
                viewModel: reader,
                layout: layout,
                navigationToken: reader.navigationToken,
                decorationsVersion: reader.decorationsVersion,
                translationID: reader.translation.id,
                chapterID: reader.chapterID
            )
        }
    }

    /// On iPad the tab bar floats at the top of the screen, so the reader's
    /// controls sit below it rather than underneath it.
    private var controlsTopClearance: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : 4
    }

    /// Stable insets from the window, so text doesn't reflow as bars show and hide.
    private var readerSafeArea: UIEdgeInsets {
        let insets = windowSafeArea ?? .zero
        // Next to the companion panel only the outer edge needs side insets.
        return isWide && showsCompanion ? UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0) : insets
    }

    private var companion: some View {
        CompanionPanel(mode: $companionMode)
            .frame(width: 360)
            .background(palette.surface.ignoresSafeArea())
    }

    // MARK: Actions

    private func turnPage(forward: Bool) -> KeyPress.Result {
        if preferences.readingMode == .page {
            reader.requestPageTurn(forward: forward)
        } else if forward {
            reader.goToNextChapter()
        } else {
            reader.goToPreviousChapter()
        }
        return .handled
    }

    private func openNoteForSelection() {
        guard entitlements.canAddNote(existing: StudyStore(context: modelContext).noteCount()) else {
            sheet = .premium(.unlimitedNotes)
            return
        }
        if let note = reader.makeNoteForSelection() {
            sheet = .note(note)
        }
    }

    /// Listen from the top of this page, or play/pause if this chapter is playing.
    private func listen() {
        if audio.isActive, audio.chapter == reader.chapterID {
            audio.togglePlayback()
            return
        }
        let verse = reader.focusVerse
        let start = verse.chapterID == reader.chapterID && verse.verse > 1 ? verse : nil
        audio.play(reader.chapterID, from: start)
    }

    /// The whole chapter being read.
    private func studyChapter() {
        let chapter = reader.chapterID
        let last = (try? reader.library.current.chapter(chapter))?.verses.last?.id.verse ?? 1
        sheet = .study(StudyPassage(chapter: chapter, lastVerse: last), .summarize)
    }

    /// The selected verses (kept within one book).
    private func explainSelection() {
        guard let first = reader.selection.min(), let last = reader.selection.max() else { return }
        let end = last.book == first.book ? last : first
        reader.clearSelection()
        sheet = .study(StudyPassage(start: first, end: end), .explain)
    }

    private func showCrossReferencesForSelection() {
        guard let verse = reader.selection.min() else { return }
        if isWide {
            reader.studyVerse = verse
            companionMode = .crossReferences
            showsCompanion = true
            reader.clearSelection()
        } else {
            sheet = .crossReferences(verse)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ReaderSheet) -> some View {
        switch sheet {
        case .chapterPicker:
            ChapterPickerView { chapter in
                reader.open(chapter)
                self.sheet = nil
            }
        case .settings:
            ReaderSettingsSheet()
                // With accessibility text sizes a half-height sheet hides most
                // options, so open it full height.
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        case let .note(note):
            NavigationStack {
                NoteEditorView(note: note)
            }
            .onDisappear { reader.notesDidChange() }
        case let .premium(feature):
            PremiumView(highlighted: feature)
        case let .study(passage, action):
            // Explaining a selection was asked for; a whole chapter waits for a tap
            // unless Premium, so a free account's daily answers aren't spent by accident.
            StudyAssistantView(passage: passage, initialAction: action, autoLoads: action == .explain || entitlements.allows(.advancedAI))
        case .audio:
            AudioSettingsView()
                .presentationDetents([.medium, .large])
        case let .crossReferences(verse):
            NavigationStack {
                CrossReferencesView(verse: verse) { target in
                    reader.open(target)
                    self.sheet = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

enum ReaderSheet: Identifiable {
    case chapterPicker
    case settings
    case note(Note)
    case crossReferences(VerseID)
    case premium(PremiumFeature)
    case study(StudyPassage, StudyAction)
    case audio

    var id: String {
        switch self {
        case .chapterPicker: "chapters"
        case .settings: "settings"
        case .audio: "audio"
        case let .note(note): "note-\(note.id)"
        case let .crossReferences(verse): "xref-\(verse.rawValue)"
        case let .premium(feature): "premium-\(feature.rawValue)"
        case let .study(passage, action): "study-\(passage.start.rawValue)-\(passage.end.rawValue)-\(action.rawValue)"
        }
    }
}
