import SwiftData
import SwiftUI

/// The Premium morning welcome: the room brightens, the greeting appears,
/// today's verse fades in, then today's reading, while the person's ambient
/// sounds ease in. With Reduce Motion everything simply appears.
struct MorningWelcomeView: View {
    /// A preview from Settings: closing goes nowhere and stops the sounds it started.
    var isPreview = false
    let close: () -> Void

    @Environment(MorningWelcome.self) private var welcome
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementService.self) private var entitlements
    @Environment(FeaturePreferences.self) private var features
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \PlanEnrollment.updatedAt, order: .reverse) private var enrollments: [PlanEnrollment]

    /// 0 dim; 1 greeting; 2 verse; 3 reading and buttons.
    @State private var stage = 0
    @State private var startedSounds = false

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                        .opacity(stage >= 1 ? 1 : 0)
                        .offset(y: stage >= 1 ? 0 : 8)
                    verse
                        .opacity(stage >= 2 ? 1 : 0)
                        .offset(y: stage >= 2 ? 0 : 12)
                    VStack(alignment: .leading, spacing: 16) {
                        if let reading = todaysReading { readingCard(reading) }
                        buttons
                    }
                    .opacity(stage >= 3 ? 1 : 0)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 48)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await reveal() }
        // Counted once it's really on screen (not when it couldn't be shown).
        .onAppear { if !isPreview { welcome.markShown() } }
    }

    // MARK: Parts

    /// The page, dim at first, brightening like morning light.
    private var background: some View {
        ZStack {
            palette.background
            RadialGradient(
                colors: [palette.accent.opacity(stage >= 1 ? 0.18 : 0), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            Color.black.opacity(stage == 0 ? 0.45 : 0)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Text(MorningWelcome.greeting(hour: Calendar.current.component(.hour, from: .now), name: name))
                .font(.system(.largeTitle, design: .serif, weight: .regular))
                .foregroundStyle(palette.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.greeting")
    }

    /// Verbatim, from the Bible being read.
    private var verse: some View {
        let id = DailyVerse.verse()
        let text = (try? library.current.verse(id))?.plainText ?? ""
        let reference = PassageReference(verse: id).description(in: library.currentTranslation.language)
        return VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(settings.preferences.font.font(size: 22))
                .lineSpacing(7)
                .foregroundStyle(palette.text)
            Text("\(reference) · \(library.currentTranslation.abbreviation)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.verse")
    }

    private struct Reading {
        let planTitle: String
        let dayTitle: String
        let first: ChapterID
    }

    private var todaysReading: Reading? {
        guard features.isOn(.plans),
              let enrollment = enrollments.first(where: { $0.isActive && $0.plan != nil }),
              let plan = enrollment.plan else { return nil }
        let progress = PlanProgress(plan: plan, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
        // todaysDay() is the first day not yet read.
        guard !progress.isComplete, let day = progress.todaysDay(),
              let first = day.spans.first?.first else { return nil }
        return Reading(planTitle: plan.title, dayTitle: day.title, first: first)
    }

    private func readingCard(_ reading: Reading) -> some View {
        Button {
            finish { router.read(reading.first) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Reading")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text(reading.dayTitle)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(palette.text)
                    Text(reading.planTitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome.todaysReading")
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                finish { router.continueReading() }
            } label: {
                Text("Continue Reading")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .accessibilityIdentifier("welcome.continue")
            Button("Not Now") { finish(nil) }
                .foregroundStyle(palette.secondaryText)
                .padding(.vertical, 6)
                .accessibilityIdentifier("welcome.close")
        }
    }

    // MARK: Behaviour

    /// The welcome's own name, else the person's name in groups.
    private var name: String? {
        MorningWelcome.firstName(welcome.name) ?? MorningWelcome.firstName(community.profile?.displayName)
    }

    private func reveal() async {
        if reduceMotion {
            stage = 3
        } else {
            for (next, pause) in [(1, 0.35), (2, 1.0), (3, 1.0)] {
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: next == 1 ? 1.8 : 1.1)) { stage = next }
            }
        }
        easeInSounds()
    }

    /// The person's own mix, faded in by the ambient player; nothing when
    /// they haven't chosen sounds or something is already playing.
    private func easeInSounds() {
        guard welcome.playsSounds, entitlements.allows(.ambientSounds), features.isOn(.ambientSounds),
              !ambient.mix.isEmpty, !ambient.isPlaying else { return }
        ambient.play()
        startedSounds = true
    }

    private func finish(_ then: (() -> Void)?) {
        if isPreview {
            if startedSounds { ambient.pause() }
            close()
            return
        }
        close()
        then?()
    }
}
