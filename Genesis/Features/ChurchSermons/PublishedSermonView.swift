import SwiftData
import SwiftUI
import UIKit

/// A church's published sermon outline: the church's words exactly as
/// published, each verified passage a tap away (a sheet, so the outline
/// keeps its place), Copy for each section, the series' previous and an
/// invitation to the next, the church's Locations and Times, the cover, the
/// person's own notes, and report or hide.
struct PublishedSermonView: View {
    let sermon: PublishedSermon
    /// Opens another sermon (the series' previous or next).
    let onOpenSermon: (String) -> Void
    /// After hiding the church's sermons.
    let onHidden: () -> Void

    @Environment(\.churchSermons) private var backend
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(HiddenChurches.self) private var hidden
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var passage: PassageRoute?
    @State private var notes: Sermon?
    @State private var copied: String?
    @State private var reporting = false
    @State private var confirmingHide = false
    @State private var reportMessage: String?
    @State private var cover: UIImage?

    private struct PassageRoute: Identifiable {
        let range: StudyRange
        let quoted: String?
        var id: String { "\(range.start.rawValue)-\(range.end.rawValue)-\(quoted ?? "")" }
    }

    var body: some View {
        let sections = SermonOutline.sections(sermon.blocks)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header { scroll(to: Self.locationsID, proxy: proxy) }
                    ForEach(sections) { section in
                        sectionView(section)
                            .id(section.id)
                    }
                    joinNext
                    locationsSection
                        .id(Self.locationsID)
                    previousLink
                    Text("Shared by \(sermon.church). Passages are shown from your Bible on this device.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.top, 28)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .toolbar { toolbar(sections, proxy: proxy) }
        }
        .themedScreen()
        .navigationTitle(sermon.church)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sermon.slug) {
            await backend.count(.open, slug: sermon.slug)
        }
        .task(id: sermon.cover?.path) { await loadCover() }
        .sheet(item: $passage) { route in
            ChurchPassageSheet(range: route.range, quoted: route.quoted) { verse in
                passage = nil
                router.read(verse)
            }
        }
        .sheet(item: $notes) { notes in
            NavigationStack { SermonEditorView(sermon: notes) }
        }
        .confirmationDialog("Report this sermon?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(ContentActions.reasons, id: \.value) { reason in
                Button(reason.title) { Task { await report(reason.value) } }
            }
        } message: {
            Text("Reports are private and go to the church's moderators.")
        }
        .confirmationDialog("Hide sermons from \(sermon.church)?", isPresented: $confirmingHide, titleVisibility: .visible) {
            Button("Hide", role: .destructive) {
                hidden.set(sermon.groupID, hidden: true)
                onHidden()
            }
        } message: {
            Text("You won't see their sermons in Versely. They aren't told, and you can show them again from one of their links.")
        }
        .alert("Report", isPresented: Binding(get: { reportMessage != nil }, set: { if !$0 { reportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportMessage ?? "")
        }
    }

    // MARK: Parts

    private static let locationsID = "churchSermon.locations"

    private func scroll(to id: String, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .top)
        } else {
            withAnimation(Motion.easeInOut(0.3)) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func header(onLocations: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cover {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(.rect(cornerRadius: 16))
                    .accessibilityElement()
                    .accessibilityLabel(sermon.cover?.alt ?? "")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHidden(sermon.cover?.decorative ?? true)
                    .padding(.bottom, 8)
            }
            Text(sermon.church)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(palette.accent)
            Text(sermon.title.isEmpty ? String(localized: "Sermon") : sermon.title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("churchSermon.title")
            ForEach(detailLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            if sermon.audience == .members {
                Label("For members of \(sermon.church)", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            Button {
                openNotes()
            } label: {
                Label(hasNotes ? "Open My Notes" : "Take Notes", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 6)
            .accessibilityIdentifier("churchSermon.notes")
            if !sermon.locations.isEmpty {
                Button(action: onLocations) {
                    Label("Locations and Times", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityHint("Shows where and when the church meets")
                .accessibilityIdentifier("churchSermon.locationsButton")
            }
        }
        .padding(.bottom, 12)
    }

    private var detailLines: [String] {
        var lines: [String] = []
        let date = sermon.preachedDate?.formatted(date: .long, time: .omitted)
        switch (sermon.speaker.isEmpty, date) {
        case (false, let date?): lines.append(String(localized: "\(sermon.speaker) · \(date)"))
        case (false, nil): lines.append(sermon.speaker)
        case (true, let date?): lines.append(date)
        case (true, nil): break
        }
        if let series = sermon.series { lines.append(String(localized: "Series: \(series)")) }
        if !sermon.location.isEmpty { lines.append(sermon.location) }
        return lines
    }

    private var hasNotes: Bool {
        ChurchSermonNotes.existing(for: sermon.id, in: modelContext) != nil
    }

    private func sectionView(_ section: SermonOutlineSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.blocks) { block in
                blockView(block)
            }
            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = SermonOutline.copyText(section.blocks)
                    copied = section.id
                } label: {
                    Label(copied == section.id ? "Copied" : "Copy", systemImage: copied == section.id ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.secondaryText)
                .accessibilityLabel(section.title.map { String(localized: "Copy: \($0)") } ?? String(localized: "Copy"))
                .accessibilityIdentifier("churchSermon.copy")
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func blockView(_ block: SermonBlock) -> some View {
        switch block {
        case let .heading(_, text, level):
            Text(text)
                .font(.system(level == 1 ? .title : .title2, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
        case let .paragraph(_, text):
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
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
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(palette.text)
                }
            }
        case let .scripture(_, reference):
            ChurchSermonReferenceRow(reference: reference, language: library.currentTranslation.language) { range in
                passage = PassageRoute(range: range, quoted: reference.translation)
                Task { await backend.count(.passage, slug: sermon.slug) }
            }
        }
    }

    /// "Join us for …": the next sermon in the series, once it's published.
    @ViewBuilder
    private var joinNext: some View {
        if let next = sermon.next {
            Button {
                onOpenSermon(next.slug)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Join us for \(next.title)")
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        if let day = next.preachedDate?.formatted(date: .long, time: .omitted) {
                            Text(day)
                                .font(.subheadline)
                                .opacity(0.9)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(palette.background)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.accent, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityIdentifier("churchSermon.next")
        }
    }

    /// Where and when the church meets, with directions in Maps. Headed
    /// "Join us" when there's no next sermon to invite people to.
    @ViewBuilder
    private var locationsSection: some View {
        if !sermon.locations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if sermon.next == nil {
                    Text("Join us")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.text)
                }
                Text("Locations and Times")
                    .font(sermon.next == nil ? Font.footnote.weight(.semibold) : Font.title3.weight(.semibold))
                    .textCase(sermon.next == nil ? Text.Case.uppercase : nil)
                    .foregroundStyle(sermon.next == nil ? palette.secondaryText : palette.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(sermon.locations.enumerated()), id: \.offset) { _, place in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.body.weight(.semibold))
                        ForEach(place.scheduleLines(today: Timestamp.dayString(from: Date())), id: \.self) { line in
                            Text(line)
                        }
                        if let url = place.mapsURL {
                            Link(destination: url) {
                                Label(place.addressLines.joined(separator: "\n"), systemImage: "mappin")
                                    .multilineTextAlignment(.leading)
                            }
                            .tint(palette.accent)
                            .accessibilityLabel(place.oneLineAddress)
                            .accessibilityHint("Opens directions in Maps")
                        }
                    }
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(palette.surface, in: .rect(cornerRadius: 16))
            .padding(.top, 24)
            .accessibilityIdentifier("churchSermon.locations")
        }
    }

    @ViewBuilder
    private var previousLink: some View {
        if let previous = sermon.previous {
            VStack(alignment: .leading, spacing: 10) {
                if let series = sermon.series {
                    Text(series)
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.secondaryText)
                }
                seriesLink(previous, label: String(localized: "Previous"), systemImage: "chevron.left", id: "churchSermon.previous")
            }
            .padding(.top, 24)
        }
    }

    private func seriesLink(_ summary: ChurchSermonSummary, label: String, systemImage: String, id: String) -> some View {
        Button {
            onOpenSermon(summary.slug)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Text(summary.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: systemImage)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(palette.surface, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ToolbarContentBuilder
    private func toolbar(_ sections: [SermonOutlineSection], proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            let titled = sections.filter { $0.title != nil }
            if titled.count > 1 {
                Menu {
                    ForEach(titled) { section in
                        Button(section.title ?? "") { scroll(to: section.id, proxy: proxy) }
                    }
                } label: {
                    Label("Jump to Section", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("churchSermon.jump")
            }
            ShareLink(item: ChurchSermonLink.url(slug: sermon.slug)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Menu {
                Button("Copy Outline", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = SermonOutline.copyText(sermon.blocks)
                }
                Button("Report", systemImage: "flag") { reporting = true }
                Button("Hide Sermons from \(sermon.church)", systemImage: "hand.raised") { confirmingHide = true }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("churchSermon.more")
        }
    }

    // MARK: Actions

    private func openNotes() {
        let isNew = !hasNotes
        notes = ChurchSermonNotes.notes(for: sermon, in: modelContext)
        if isNew { Task { await backend.count(.save, slug: sermon.slug) } }
    }

    private func report(_ reason: String) async {
        do {
            try await backend.report(slug: sermon.slug, reason: reason)
            reportMessage = String(localized: "Thank you. The church's moderators will review it.")
        } catch {
            reportMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "Something went wrong. Please try again.")
        }
    }

    private func loadCover() async {
        guard let path = sermon.cover?.path else {
            cover = nil
            return
        }
        // Asked for each time it's shown, so access is checked again; never saved.
        if let data = try? await backend.cover(path: path), let image = UIImage(data: data) {
            cover = image
        }
    }
}

/// A Scripture reference in the outline: a verified one opens the passage;
/// others stay as the pastor wrote them.
struct ChurchSermonReferenceRow: View {
    let reference: SermonReference
    /// The language to name the passage in (the person's Bible's).
    let language: String
    let onOpen: (StudyRange) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let label = reference.label.map { " \u{00B7} \($0)" } ?? ""
        if let range = reference.range {
            Button {
                onOpen(range)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "book")
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Text(reference.raw).foregroundStyle(palette.accent).fontWeight(.semibold))\(Text(label).foregroundStyle(palette.secondaryText))")
                        let named = range.description(in: language)
                        if named != reference.raw {
                            Text(named)
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .frame(minHeight: 48)
                .background(palette.surface, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the passage")
            .accessibilityIdentifier("churchSermon.passage")
        } else {
            Text("\(Text(reference.raw).fontWeight(.medium).foregroundStyle(palette.text))\(Text(label).foregroundStyle(palette.secondaryText))")
                .padding(.vertical, 4)
        }
    }
}
