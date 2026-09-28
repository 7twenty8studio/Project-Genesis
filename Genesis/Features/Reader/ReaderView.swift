import SwiftData
import SwiftUI
import UIKit

/// The heart of the app: distraction-free reading with controls that appear
/// on tap. On wide screens (iPad, iPhone Duo open) a companion panel sits
/// beside the text for notes, cross references and search.
struct ReaderView: View {
    @Environment(ReaderViewModel.self) private var reader
    @Environment(ReaderSettings.self) private var settings
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

                if reader.showsControls && !reader.isSelecting {
                    ReaderControls(
                        showsCompanionToggle: isWide,
                        onChapterPicker: { sheet = .chapterPicker },
                        onSettings: { sheet = .settings },
                        onToggleCompanion: { showsCompanion.toggle() }
                    )
                    .padding(.top, readerSafeArea.top + 4)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                }

                if reader.isSelecting {
                    SelectionActionBar(
                        onNote: openNoteForSelection,
                        onCrossReferences: showCrossReferencesForSelection
                    )
                    .padding(.bottom, readerSafeArea.bottom + 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
            // Rotation changes which edges have insets.
            windowSafeArea = DeviceScreen.safeAreaInsets
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
        if let note = reader.makeNoteForSelection() {
            sheet = .note(note)
        }
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
                .presentationDetents([.medium, .large])
        case let .note(note):
            NavigationStack {
                NoteEditorView(note: note)
            }
            .onDisappear { reader.notesDidChange() }
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

    var id: String {
        switch self {
        case .chapterPicker: "chapters"
        case .settings: "settings"
        case let .note(note): "note-\(note.id)"
        case let .crossReferences(verse): "xref-\(verse.rawValue)"
        }
    }
}
