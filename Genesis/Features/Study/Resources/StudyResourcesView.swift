import SwiftUI

/// The Study Library: study notes, commentaries, Bible dictionaries and
/// lexicons to download. Each is optional and works offline once it's on the
/// device. Premium packs need `.wordStudy`.
struct StudyResourcesView: View {
    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var hasLoaded = false
    @State private var removing: DownloadableStudyResource?

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section {
                    } footer: {
                        Text("Download the study helps you'd like. Each works offline once it's on your device, and you can remove it any time.")
                    }

                    ForEach(StudyResourceKind.allCases, id: \.self) { kind in
                        let items = items(kind)
                        if !items.isEmpty {
                            Section(kind.title) {
                                ForEach(items) { item in
                                    StudyResourceCard(item: item, removing: $removing)
                                }
                            }
                        }
                    }

                    if !hasLoaded {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if resources.catalog.isEmpty {
                        Section {
                            Text("Connect to the internet to see the study resources you can download.")
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }

                    if let error = resources.downloadError {
                        Section {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Study Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("studyResources.done")
                }
            }
            .navigationDestination(for: StudyBrowseRoute.self) { route in
                StudyArticleBrowserView(pack: route.pack)
            }
            .navigationDestination(for: StudyResourceDetailRoute.self) { route in
                StudyResourceDetailView(item: route.item)
            }
            .task {
                await resources.refreshCatalog()
                hasLoaded = true
            }
            .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let removing { resources.remove(removing.id) }
                }
            } message: {
                Text("You can download it again any time.")
            }
        }
    }

    /// A kind's packs, those in the app's language first.
    private func items(_ kind: StudyResourceKind) -> [DownloadableStudyResource] {
        let all = resources.all.filter { $0.kind == kind }
        return all.filter { $0.language == AppLanguage.code } + all.filter { $0.language != AppLanguage.code }
    }
}

struct StudyBrowseRoute: Hashable {
    let pack: String
}

struct StudyResourceDetailRoute: Hashable {
    let item: DownloadableStudyResource
}

/// One pack: its name, author and tradition, what it is, and a Download button.
struct StudyResourceCard: View {
    let item: DownloadableStudyResource
    @Binding var removing: DownloadableStudyResource?

    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @State private var premium: PremiumFeature?

    private var isInstalled: Bool { resources.isInstalled(item.id) }
    private var locked: Bool { item.premium && !entitlements.allows(.wordStudy) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                action
            }
            if !item.localizedSummary.isEmpty {
                Text(item.localizedSummary)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                if item.kind == .notes || item.kind == .dictionary, isInstalled, !locked {
                    NavigationLink(value: StudyBrowseRoute(pack: item.id)) {
                        Label("Browse", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("studyResources.browse.\(item.id)")
                }
                NavigationLink(value: StudyResourceDetailRoute(item: item)) {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier("studyResources.about.\(item.id)")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(palette.accent)
        }
        .padding(.vertical, 6)
        .swipeActions {
            if isInstalled {
                Button("Remove", role: .destructive) { removing = item }
            }
        }
        .contextMenu {
            if isInstalled {
                Button("Remove from This Device", systemImage: "trash", role: .destructive) { removing = item }
            }
        }
        .premiumSheet($premium)
    }

    /// "Matthew Henry · 1706 · Puritan · 11.7 MB".
    private var subtitle: String {
        var parts: [String] = []
        if !item.author.isEmpty { parts.append(item.author) }
        if let year = item.year, !year.isEmpty { parts.append(year) }
        if let tradition = item.tradition { parts.append(tradition.title) }
        if item.language != AppLanguage.code { parts.append(AppLanguage.displayName(item.language)) }
        if isInstalled {
            parts.append(String(localized: "On this device"))
        } else {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.fileBytes), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var action: some View {
        if resources.downloading.contains(item.id) {
            ProgressView()
                .accessibilityLabel(isInstalled ? String(localized: "Updating") : String(localized: "Downloading"))
        } else if isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.accent)
                .accessibilityLabel(String(localized: "On this device"))
                .accessibilityIdentifier("studyResources.installed.\(item.id)")
        } else if locked {
            Button {
                premium = .wordStudy
            } label: {
                Label("Premium", systemImage: "lock")
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .accessibilityLabel(String(localized: "Unlock \(item.name) with Premium"))
            .accessibilityIdentifier("studyResources.unlock.\(item.id)")
        } else {
            Button {
                Task { await resources.download(item) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .accessibilityLabel(String(localized: "Download \(item.name)"))
            .accessibilityIdentifier("studyResources.download.\(item.id)")
        }
    }
}

/// A pack's details: who wrote it, its tradition, its license and credit.
struct StudyResourceDetailView: View {
    let item: DownloadableStudyResource

    @Environment(\.palette) private var palette

    var body: some View {
        List {
            ThemedRows {
                Section {
                    if !item.localizedSummary.isEmpty {
                        Text(item.localizedSummary).foregroundStyle(palette.text)
                    }
                    if !item.author.isEmpty {
                        LabeledContent("Author", value: item.author)
                    }
                    if let year = item.year, !year.isEmpty {
                        LabeledContent("Published", value: year)
                    }
                    if let tradition = item.tradition {
                        LabeledContent("Tradition", value: tradition.title)
                    }
                    LabeledContent("Language", value: AppLanguage.displayName(item.language))
                    LabeledContent("Download size", value: ByteCountFormatter.string(fromByteCount: Int64(item.fileBytes), countStyle: .file))
                    LabeledContent("Access", value: item.premium ? String(localized: "Premium") : String(localized: "Free"))
                }
                Section("License") {
                    Text(item.license).foregroundStyle(palette.text)
                    if !item.attribution.isEmpty {
                        Text(item.attribution)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                if item.kind == .commentary {
                    Section {
                    } footer: {
                        Text("Commentaries are one writer's explanation of Scripture, shown apart from the Bible's text. Read them alongside the Bible, not in place of it.")
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
