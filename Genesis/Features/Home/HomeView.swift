import SwiftData
import SwiftUI

/// A calm starting place: continue reading, today's verse, recent highlights
/// and notes, and the Bibles on this device.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(ReadingProgress.self) private var progress
    @Environment(ReaderSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementService.self) private var entitlements
    @State private var showsBibles = false
    @State private var showsSettings = false
    @State private var showsYearInReview = false
    @Environment(\.searchIsTab) private var searchIsTab
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(StudyAssistant.self) private var assistant
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    @Query(HomeView.recentHighlightsQuery) private var recentHighlights: [Highlight]
    @Query(HomeView.recentNotesQuery) private var recentNotes: [Note]
    @Query(sort: \PlanEnrollment.updatedAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @Query(filter: #Predicate<Prayer> { !$0.isAnswered }) private var activePrayers: [Prayer]
    @Query private var memoryVerses: [MemoryVerse]
    @State private var editingNote: Note?
    @State private var premium: PremiumFeature?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    if YearInReview.isSeason(), progress.hasStartedReading { yearInReviewCard }
                    continueReading
                    if features.isOn(.plansAndPrayer) { todaysReading }
                    dailyVerse
                    if features.isOn(.plansAndPrayer) { prayerJournal }
                    if features.isOn(.plansAndPrayer) { memorise }
                    readingProgress
                    if !recentHighlights.isEmpty { highlights }
                    if !recentNotes.isEmpty { notes }
                    bibles
                    if !entitlements.isPremium { premiumCard }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .overlay { ChapterMomentOverlay(place: .home).ignoresSafeArea(edges: .top) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingNote) { note in
                NavigationStack { NoteEditorView(note: note) }
            }
            .sheet(isPresented: $showsBibles) { BibleDownloadsView() }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showsYearInReview) { YearInReviewView(year: YearInReview.reviewedYear()) }
            .sheet(isPresented: $router.showsAccount) {
                AccountView()
            }
            .premiumSheet($premium)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .plans: PlansView()
                case let .plan(id): PlanDetailView(enrollmentID: id)
                case .prayerJournal: PrayerJournalView()
                case .insights: InsightsView()
                case .memorise:
                    if entitlements.allows(.memorise) {
                        MemoriseView()
                    } else {
                        PremiumView(highlighted: .memorise)
                    }
                }
            }
        }
    }

    // MARK: Sections

    /// December and January: "Your 2026 in review".
    private var yearInReviewCard: some View {
        Button {
            showsYearInReview = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your \(String(YearInReview.reviewedYear())) in Review")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text("Look back on your year of reading, highlights and prayer.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(18)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.yearInReview")
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Text(greetingText)
                    .font(.system(.largeTitle, design: .serif, weight: .regular))
                    .foregroundStyle(palette.text)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if !searchIsTab { SearchButton() }
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
            Button {
                router.showsAccount = true
            } label: {
                Image(systemName: auth.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(auth.isSignedIn ? "Account, signed in" : "Account, sign in to sync")
            .accessibilityIdentifier("home.account")
        }
        .padding(.top, 24)
    }

    // MARK: Plans, prayer, progress

    private var activeEnrollment: PlanEnrollment? {
        enrollments.first { $0.isActive && $0.plan != nil }
    }

    @ViewBuilder
    private var todaysReading: some View {
        if let enrollment = activeEnrollment, let plan = enrollment.plan {
            let planProgress = PlanProgress(plan: plan, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Today's Reading"), action: (String(localized: "All Plans"), { router.homePath.append(.plans) }))
                VStack(alignment: .leading, spacing: 10) {
                    Text(plan.title)  // follows the app's language for built-in plans
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                    if planProgress.isComplete {
                        Label("Plan complete", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(palette.text)
                    } else if let today = planProgress.todaysDay() {
                        let doneToday = enrollment.completedDays.contains(today.number)
                        Text(today.title)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.text)
                        HStack {
                            Button {
                                if let first = today.spans.first { router.read(first.first) }
                            } label: {
                                Label("Read", systemImage: "book")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                StudyStore(context: modelContext).setDay(today.number, completed: !doneToday, in: enrollment)
                                if !doneToday { ChapterMoments.shared.planDayCompleted(today.number, planID: enrollment.id.uuidString, in: .home) }
                            } label: {
                                Label(doneToday ? "Done" : "Mark as Read", systemImage: doneToday ? "checkmark.circle.fill" : "checkmark")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("home.markRead")
                        }
                    }
                    ProgressView(value: planProgress.fractionComplete)
                        .tint(palette.accent)
                        .accessibilityLabel("Plan progress")
                }
                .card()
                .contentShape(Rectangle())
                .onTapGesture { router.homePath.append(.plan(enrollment.id)) }
            }
        } else {
            Button {
                router.homePath.append(.plans)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading Plans")
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        Text("Read the whole Bible in a year, or a book at a time.")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(palette.secondaryText)
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.plans")
        }
    }

    private var prayerJournal: some View {
        Button {
            router.homePath.append(.prayerJournal)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "hands.and.sparkles")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayer Journal")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    prayerSummary
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.prayer")
    }

    /// Memorise Scripture (Premium).
    private var memorise: some View {
        let unlocked = entitlements.allows(.memorise)
        let due = memoryVerses.filter { $0.isDue() }.count
        return Button {
            if unlocked {
                router.homePath.append(.memorise)
            } else {
                premium = .memorise
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memorise Scripture")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Group {
                        if !unlocked || memoryVerses.isEmpty {
                            Text("Learn verses by heart, a minute a day.")
                        } else if due == 0 {
                            Text("All caught up for today")
                        } else {
                            Text("\(due) to review today")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !unlocked { PremiumBadge() }
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.memorise")
    }

    private var prayerSummary: Text {
        if activePrayers.isEmpty {
            Text("Keep a private record of what you're praying for.")
        } else if activePrayers.count == 1 {
            Text("1 prayer you're holding up")
        } else {
            Text("\(activePrayers.count) prayers you're holding up")
        }
    }

    @ViewBuilder
    private var readingProgress: some View {
        if progress.hasStartedReading {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Progress"), action: (String(localized: "Insights"), { router.homePath.append(.insights) }))
                HStack(spacing: 12) {
                    stat(value: progress.streak(), label: String(localized: "day streak"), symbol: "flame")
                    stat(value: progress.chaptersRead.count, label: String(localized: "chapters read"), symbol: "book.pages")
                    stat(value: progress.booksCompleted, label: String(localized: "books finished"), symbol: "books.vertical")
                }
            }
        }
    }

    private var premiumCard: some View {
        Button {
            premium = .historicalContent
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Genesis Premium")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text(assistant.isEnabled ? "The study assistant, family trees and maps, Memorise and more." : "Family trees and maps, Memorise, ambient sounds and more.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.premium")
    }

    private func stat(value: Int, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(palette.accent)
            Text("\(value)")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    private var continueReading: some View {
        let position = progress.position
        let verse = try? library.current.verse(position)
        return Button {
            router.continueReading()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(progress.hasStartedReading ? "Continue Reading" : "Begin Reading")
                        .font(.caption.weight(.semibold))
                        .kerning(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.accent)
                    Spacer()
                    Image(systemName: "book")
                        .foregroundStyle(palette.accent)
                }
                Text(position.chapterID.description)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let verse {
                    Text(verse.plainText)
                        .font(settings.preferences.font.font(size: 16))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                ProgressView(value: progress.progressThroughBook)
                    .tint(palette.accent)
                    .accessibilityLabel("Progress through \(position.chapterID.bibleBook.name)")
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var dailyVerse: some View {
        let id = DailyVerse.verse()
        let verse = try? library.current.verse(id)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Verse of the Day"))
            Button {
                router.read(id)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verse?.plainText ?? "")
                        .font(settings.preferences.font.font(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    Text("\(PassageReference(verse: id).description) · \(library.currentTranslation.abbreviation)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [palette.surface, palette.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.accent.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let verse {
                    ShareLink(item: ChapterTextBuilder.shareText(for: [verse], translation: library.currentTranslation))
                }
            }
        }
    }

    private var highlights: some View {
        let texts = (try? library.current.verses(withIDs: recentHighlights.map(\.verse))) ?? [:]
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Recently Highlighted"), action: (String(localized: "See All"), { router.tab = .library }))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recentHighlights) { highlight in
                        Button {
                            router.read(highlight.verse)
                        } label: {
                            VerseSnippet(
                                reference: PassageReference(verse: highlight.verse).description,
                                text: texts[highlight.verse]?.plainText ?? "",
                                highlight: highlight.color,
                                lineLimit: 4
                            )
                            .frame(width: 240, alignment: .topLeading)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Recent Notes"), action: (String(localized: "See All"), { router.tab = .library }))
            VStack(spacing: 0) {
                ForEach(recentNotes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        NoteListRow(note: note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if note.id != recentNotes.last?.id {
                        Divider().overlay(palette.separator)
                    }
                }
            }
            .card()
        }
    }

    private var bibles: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Bibles on This Device"), action: (String(localized: "Get More"), { showsBibles = true }))
            VStack(spacing: 0) {
                ForEach(library.translations) { translation in
                    Button {
                        router.reader.switchTranslation(to: translation)
                    } label: {
                        HStack(spacing: 14) {
                            Text(translation.abbreviation)
                                .font(.system(.subheadline, design: .serif, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(translation.name)
                                    .foregroundStyle(palette.text)
                                Text(library.isAvailableOffline(translation) ? "Available offline" : "Not downloaded")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            if translation == library.currentTranslation {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                                    .accessibilityLabel("Current translation")
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    // MARK: Queries

    private static var recentHighlightsQuery: FetchDescriptor<Highlight> {
        var descriptor = FetchDescriptor<Highlight>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 10
        return descriptor
    }

    private static var recentNotesQuery: FetchDescriptor<Note> {
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 3
        return descriptor
    }
}
