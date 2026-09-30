import SwiftData
import SwiftUI

/// Plans the person is following, plus plans they can start.
struct PlansView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @State private var showsCustomPlan = false
    @State private var pendingPlan: ReadingPlan?

    var body: some View {
        List {
            if !enrollments.isEmpty {
                Section("Your Plans") {
                    ForEach(enrollments) { enrollment in
                        NavigationLink(value: HomeRoute.plan(enrollment.id)) {
                            EnrollmentRow(enrollment: enrollment)
                        }
                        .listRowBackground(palette.surface)
                    }
                    .onDelete { offsets in
                        let store = StudyStore(context: modelContext)
                        offsets.map { enrollments[$0] }.forEach { store.delete($0) }
                    }
                }
            }

            Section("Start a Plan") {
                ForEach(ReadingPlan.builtIns) { plan in
                    Button {
                        pendingPlan = plan
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.headline)
                                .foregroundStyle(palette.text)
                            Text(plan.summary)
                                .font(.subheadline)
                                .foregroundStyle(palette.secondaryText)
                            Text("\(plan.dayCount) days")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("plans.start.\(plan.id)")
                    .listRowBackground(palette.surface)
                }

                Button {
                    showsCustomPlan = true
                } label: {
                    Label("Create Your Own Plan", systemImage: "plus")
                }
                .accessibilityIdentifier("plans.custom")
                .listRowBackground(palette.surface)
            }
        }
        .themedScreen()
        .navigationTitle("Reading Plans")
        .confirmationDialog(
            pendingPlan?.title ?? "",
            isPresented: Binding(get: { pendingPlan != nil }, set: { if !$0 { pendingPlan = nil } }),
            titleVisibility: .visible,
            presenting: pendingPlan
        ) { plan in
            Button("Start Today") { start(plan) }
                .accessibilityIdentifier("plans.confirmStart")
        } message: { plan in
            Text(plan.summary)
        }
        .sheet(isPresented: $showsCustomPlan) {
            CustomPlanView { plan in start(plan) }
        }
    }

    private func start(_ plan: ReadingPlan) {
        let enrollmentID = StudyStore(context: modelContext).start(plan).id
        pendingPlan = nil
        // On iPad the dialog is a popover (and custom plans come from a sheet).
        // Pushing while it's still closing can leave the next tap swallowed, so
        // open the plan once the dismissal has finished.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            router.homePath.append(.plan(enrollmentID))
        }
    }
}

private struct EnrollmentRow: View {
    let enrollment: PlanEnrollment
    @Environment(\.palette) private var palette

    var body: some View {
        let progress = enrollment.plan.map {
            PlanProgress(plan: $0, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text(enrollment.title)
                .font(.headline)
                .foregroundStyle(palette.text)
            if let progress {
                if progress.isComplete {
                    Label("Completed", systemImage: "checkmark.seal")
                        .font(.subheadline)
                        .foregroundStyle(palette.accent)
                } else if let today = progress.todaysDay() {
                    Text("Day \(today.number): \(today.title)")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                ProgressView(value: progress.fractionComplete)
                    .tint(palette.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One plan: today's reading, every day with checkmarks, restart and remove.
struct PlanDetailView: View {
    let enrollmentID: UUID

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [PlanEnrollment]
    @State private var confirmRestart = false
    @State private var confirmDelete = false

    init(enrollmentID: UUID) {
        self.enrollmentID = enrollmentID
        _matches = Query(filter: #Predicate<PlanEnrollment> { $0.id == enrollmentID })
    }

    var body: some View {
        if let enrollment = matches.first, let plan = enrollment.plan {
            content(enrollment: enrollment, plan: plan)
        } else {
            QuietEmptyState(systemImage: "book.closed", title: "Plan not found", message: "It may have been removed on another device.")
                .themedScreen()
        }
    }

    private func content(enrollment: PlanEnrollment, plan: ReadingPlan) -> some View {
        let progress = PlanProgress(plan: plan, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
        let store = StudyStore(context: modelContext)
        let scheduled = progress.scheduledDay()

        return Group {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if progress.isComplete {
                            Label("You finished this plan", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(palette.accent)
                        } else if let today = progress.todaysDay() {
                            Text("TODAY \u{00B7} DAY \(today.number) OF \(plan.dayCount)")
                                .font(.caption.weight(.semibold))
                                .kerning(1.1)
                                .foregroundStyle(palette.accent)
                            Text(today.title)
                                .font(.system(.title2, design: .serif, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .accessibilityIdentifier("plan.todayTitle")
                            HStack {
                                Button {
                                    if let first = today.spans.first { router.read(first.first) }
                                } label: {
                                    Label("Read", systemImage: "book")
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("plan.read")

                                Button {
                                    store.setDay(today.number, completed: true, in: enrollment)
                                } label: {
                                    Label("Mark as Read", systemImage: "checkmark")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("plan.markRead")
                            }
                            let behind = progress.daysBehind()
                            if behind > 0 {
                                Text(behind == 1 ? "1 earlier day to catch up on" : "\(behind) earlier days to catch up on")
                                    .font(.footnote)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                        ProgressView(value: progress.fractionComplete) {
                            Text("\(Int(progress.fractionComplete * 100))% complete")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                        .tint(palette.accent)
                        .accessibilityIdentifier("plan.progress")
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(palette.surface)
                }

                Section("All Days") {
                    ForEach(plan.days, id: \.number) { day in
                        DayRow(
                            day: day,
                            isComplete: enrollment.completedDays.contains(day.number),
                            isToday: day.number == scheduled,
                            onToggle: { store.setDay(day.number, completed: !enrollment.completedDays.contains(day.number), in: enrollment) },
                            onRead: { if let first = day.spans.first { router.read(first.first) } }
                        )
                        .id(day.number)
                        .listRowBackground(palette.surface)
                    }
                }

                Section {
                    Button("Restart Plan") { confirmRestart = true }
                    Button("Remove Plan", role: .destructive) { confirmDelete = true }
                }
            }
            .themedScreen()
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Restart from today?", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("Restart", role: .destructive) { store.restart(enrollment) }
            } message: {
                Text("Your checkmarks for this plan will be cleared.")
            }
            .confirmationDialog("Remove this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    store.delete(enrollment)
                    dismiss()
                }
            }
        }
    }
}

private struct DayRow: View {
    let day: PlanDay
    let isComplete: Bool
    let isToday: Bool
    let onToggle: () -> Void
    let onRead: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isComplete ? palette.accent : palette.separator)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isComplete ? "Day \(day.number), read" : "Day \(day.number), not read")
            .accessibilityHint("Toggles whether this day is read")

            Button(action: onRead) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(day.number)\(isToday ? " \u{00B7} Today" : "")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? palette.accent : palette.secondaryText)
                    Text(day.title)
                        .foregroundStyle(palette.text)
                        .strikethrough(isComplete, color: palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Build a plan from chosen books and a number of days.
struct CustomPlanView: View {
    let onCreate: (ReadingPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var title = ""
    @State private var selectedBooks: Set<Int> = []
    @State private var days = 30

    private var orderedBooks: [Int] { selectedBooks.sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Paul's Letters", text: $title)
                        .accessibilityIdentifier("customPlan.name")
                }
                Section {
                    Stepper("\(days) days", value: $days, in: 1...730)
                    if !selectedBooks.isEmpty {
                        Text(ReadingPlan.customSummary(books: orderedBooks, days: days))
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                ForEach(Testament.allCases, id: \.self) { testament in
                    Section(testament.title) {
                        let books = testament == .old ? BibleBook.oldTestament : BibleBook.newTestament
                        Button(books.allSatisfy { selectedBooks.contains($0.id) } ? "Clear All" : "Select All") {
                            let ids = Set(books.map(\.id))
                            if ids.isSubset(of: selectedBooks) { selectedBooks.subtract(ids) } else { selectedBooks.formUnion(ids) }
                        }
                        ForEach(books) { book in
                            Button {
                                if selectedBooks.contains(book.id) { selectedBooks.remove(book.id) } else { selectedBooks.insert(book.id) }
                            } label: {
                                HStack {
                                    Text(book.name).foregroundStyle(palette.text)
                                    Spacer()
                                    if selectedBooks.contains(book.id) {
                                        Image(systemName: "checkmark").foregroundStyle(palette.accent)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedBooks.contains(book.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", systemImage: "checkmark") {
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(ReadingPlan.custom(title: name.isEmpty ? "My Plan" : name, books: orderedBooks, days: days))
                        dismiss()
                    }
                    .disabled(selectedBooks.isEmpty)
                    .accessibilityIdentifier("customPlan.start")
                }
            }
        }
    }
}
