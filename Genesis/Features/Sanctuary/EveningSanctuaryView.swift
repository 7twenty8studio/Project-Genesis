import SwiftUI

/// Evening Sanctuary (Premium): the chapter in large, warm type on a dim,
/// candle-lit page, with the person's ambient sounds and a sleep timer that
/// fades everything out and closes gently. The text is verbatim from the
/// Bible database; with Reduce Motion the candle glow holds still.
struct EveningSanctuaryView: View {
    let startVerse: VerseID

    @Environment(ReaderViewModel.self) private var reader
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(EntitlementService.self) private var entitlements
    @Environment(FeaturePreferences.self) private var features
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .title3) private var textSize: CGFloat = 23

    @State private var chapterID: ChapterID
    @State private var chapter: Chapter?
    @State private var scrolledVerse: VerseID?
    @State private var startedSounds = false
    @State private var sleepMinutes: Int?
    @State private var sleepEndsAt: Date?
    @State private var isClosing = false
    @State private var showsSounds = false

    init(startVerse: VerseID) {
        self.startVerse = startVerse
        _chapterID = State(initialValue: startVerse.chapterID)
    }

    var body: some View {
        ZStack {
            SanctuaryBackground(animates: !reduceMotion)
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 76)
                    .padding(.bottom, 150)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledVerse, anchor: .top)
            topBar
            bottomBar
            Color.black
                .opacity(isClosing ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isClosing)
        }
        .preferredColorScheme(.dark)
        .task(id: chapterID) { await load() }
        .task { easeInSounds() }
        .task(id: sleepEndsAt) { await waitForSleepTimer() }
        .onChange(of: ambient.isPlaying) { _, playing in
            if playing { followSleepTimer() }
        }
        .sheet(isPresented: $showsSounds) {
            AmbientSoundsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Text

    private var font: ReaderFont { settings.preferences.font }
    private var language: String { library.currentTranslation.language }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let chapter {
                ForEach(chapter.verses) { verse in
                    verseView(verse, heading: chapter.headings.first(where: { $0.beforeVerse == verse.id.verse })?.text)
                }
                chapterButtons
                focusTip
            }
        }
        .scrollTargetLayout()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.title3)
                .foregroundStyle(SanctuaryColors.candle)
            Text(verbatim: PremiumFeature.eveningSanctuary.title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundStyle(SanctuaryColors.muted)
            Text(verbatim: chapterID.description(in: language))
                .font(font.font(size: 30, weight: .semibold))
                .foregroundStyle(SanctuaryColors.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sanctuary.title")
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private func verseView(_ verse: Verse, heading: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading {
                Text(verbatim: heading)
                    .italic()
                    .font(font.font(size: textSize * 0.75))
                    .foregroundStyle(SanctuaryColors.muted)
            }
            Text(numbered(verse))
                .font(font.font(size: textSize))
                .lineSpacing(textSize * 0.4)
                .foregroundStyle(SanctuaryColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sanctuary.verse.\(verse.id.verse)")
        }
    }

    /// The verse with its small raised number. The verse's words are verbatim.
    private func numbered(_ verse: Verse) -> AttributedString {
        var number = AttributedString("\(verse.id.verse) ")
        number.font = .system(size: max(11, textSize * 0.5), weight: .semibold)
        number.foregroundColor = SanctuaryColors.candle
        number.baselineOffset = textSize * 0.3
        return number + AttributedString(verse.text)
    }

    private var chapterButtons: some View {
        HStack {
            if let previous = chapterID.previous {
                Button { go(to: previous) } label: {
                    Label("Previous chapter", systemImage: "chevron.left")
                }
            }
            Spacer(minLength: 12)
            if let next = chapterID.next {
                Button { go(to: next) } label: {
                    Label("Next chapter", systemImage: "chevron.right")
                }
                .accessibilityIdentifier("sanctuary.next")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(SanctuaryColors.candle)
        .padding(.top, 24)
    }

    /// Apps can't turn on a Focus, so a quiet word about doing it.
    private var focusTip: some View {
        Label("To keep notifications quiet, turn on Do Not Disturb or another Focus in Control Centre.", systemImage: "moon.zzz")
            .font(.footnote)
            .foregroundStyle(SanctuaryColors.muted)
            .padding(.top, 8)
            .accessibilityIdentifier("sanctuary.focusTip")
    }

    // MARK: Controls

    private var topBar: some View {
        HStack {
            Button(action: leave) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("sanctuary.close")
            Spacer()
        }
        .foregroundStyle(SanctuaryColors.text)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            if allowsSounds { soundsMenu }
            sleepTimerMenu
        }
        .foregroundStyle(SanctuaryColors.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var allowsSounds: Bool {
        entitlements.allows(.ambientSounds) && features.isOn(.listen)
    }

    private var soundsMenu: some View {
        Menu {
            if !ambient.mix.isEmpty {
                Button(ambient.isPlaying ? "Pause Sounds" : "Play Sounds", systemImage: ambient.isPlaying ? "pause" : "play") {
                    ambient.togglePlayback()
                }
            }
            Button("Choose Sounds", systemImage: "slider.horizontal.3") { showsSounds = true }
        } label: {
            Image(systemName: ambient.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.body.weight(.medium))
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ambient sounds")
        .accessibilityIdentifier("sanctuary.sounds")
    }

    private var sleepTimerMenu: some View {
        Menu {
            Picker(selection: Binding(get: { sleepMinutes }, set: { setSleepTimer($0) })) {
                Text("Off").tag(Int?.none)
                ForEach(EveningSanctuary.sleepTimerChoices, id: \.self) { minutes in
                    Text("\(minutes) minutes").tag(Int?.some(minutes))
                }
            } label: {
                Label("Sleep Timer", systemImage: "moon.zzz")
            }
        } label: {
            sleepTimerLabel
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityIdentifier("sanctuary.sleepTimer")
    }

    private var sleepTimerLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: sleepEndsAt == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.body.weight(.medium))
            if let sleepEndsAt {
                Text(sleepEndsAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 44, minHeight: 40)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func load() async {
        chapter = reader.loadChapter(chapterID)
        // Opened mid-chapter: begin at the verse the reader was on.
        let target = startVerse.chapterID == chapterID ? startVerse : chapterID.firstVerse
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        scrolledVerse = target
    }

    /// Moving on in the sanctuary moves the reader too (and counts as reading).
    private func go(to next: ChapterID) {
        reader.open(next)
        chapterID = next
    }

    /// The person's own mix eases in; nothing when they haven't chosen
    /// sounds or something is already playing.
    private func easeInSounds() {
        guard allowsSounds, !ambient.mix.isEmpty, !ambient.isPlaying else { return }
        ambient.play()
        startedSounds = true
    }

    private func setSleepTimer(_ minutes: Int?) {
        sleepMinutes = minutes
        sleepEndsAt = EveningSanctuary.sleepTimerEnd(minutes: minutes, from: .now)
        // The ambient player fades the sounds out itself, even if the
        // sanctuary has been closed by then.
        if ambient.isPlaying { ambient.setTimer(minutes: minutes) }
    }

    /// Sounds started after the timer was set fade with it too.
    private func followSleepTimer() {
        guard let sleepEndsAt else { return }
        let minutes = Int((sleepEndsAt.timeIntervalSinceNow / 60).rounded(.up))
        if minutes > 0 { ambient.setTimer(minutes: minutes) }
    }

    private func waitForSleepTimer() async {
        guard let sleepEndsAt else { return }
        let wait = sleepEndsAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled else { return }
        await closeGently()
    }

    /// The sounds fade, the room goes dark, and the sanctuary closes.
    private func closeGently() async {
        ambient.pause()
        withAnimation(.easeInOut(duration: EveningSanctuary.closingFade)) { isClosing = true }
        try? await Task.sleep(for: .seconds(EveningSanctuary.closingFade))
        dismiss()
    }

    private func leave() {
        // Sounds the sanctuary started stop with it, unless a sleep timer
        // is fading them out later.
        if startedSounds, sleepEndsAt == nil { ambient.pause() }
        dismiss()
    }
}

/// The candle-lit palette: warm, dim and low in contrast at the edges.
enum SanctuaryColors {
    static let night = Color(uiColor: UIColor(hex: 0x16100B))
    static let flame = Color(uiColor: UIColor(hex: 0xE3A04F))
    static let ember = Color(uiColor: UIColor(hex: 0xB9683A))
    static let candle = Color(uiColor: UIColor(hex: 0xD8B077))
    static let text = Color(uiColor: UIColor(hex: 0xEADCC6))
    static let muted = Color(uiColor: UIColor(hex: 0xA8957B))
}

/// A dark room with a candle's glow at the foot of the page that breathes
/// and flickers slowly (still with Reduce Motion).
private struct SanctuaryBackground: View {
    let animates: Bool

    @State private var breathe = false
    @State private var flicker = false

    var body: some View {
        ZStack {
            SanctuaryColors.night
            RadialGradient(colors: [SanctuaryColors.flame.opacity(0.24), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: 520)
                .opacity(breathe ? 1 : 0.75)
                .scaleEffect(breathe ? 1.06 : 1, anchor: .bottom)
            RadialGradient(colors: [SanctuaryColors.ember.opacity(0.14), .clear], center: UnitPoint(x: 0.4, y: 1.0), startRadius: 0, endRadius: 300)
                .opacity(flicker ? 1 : 0.55)
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard animates else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { flicker = true }
        }
    }
}
