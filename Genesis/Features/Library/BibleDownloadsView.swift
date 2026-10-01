import SwiftUI

/// Bibles on this device and more to download. Downloads are kept offline
/// for good and updated automatically when a corrected edition comes out.
struct BibleDownloadsView: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var removing: Translation?
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.translations) { translation in
                        row(translation)
                    }
                } header: {
                    Text("On this device")
                } footer: {
                    Text("Every Bible here works offline.")
                }
                .listRowBackground(palette.surface)

                Section {
                    if !hasLoaded {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if library.available.isEmpty {
                        Text(library.catalog.isEmpty ? "Connect to the internet to see more Bibles." : "You have every Bible that's available.")
                            .foregroundStyle(palette.secondaryText)
                    }
                    ForEach(library.available) { item in
                        downloadRow(item)
                    }
                } header: {
                    Text("Available to download")
                } footer: {
                    if let error = library.downloadError {
                        Text(error).foregroundStyle(.orange)
                    } else {
                        Text("Genesis offers public-domain translations. More will come as licenses allow.")
                    }
                }
                .listRowBackground(palette.surface)
            }
            .themedScreen()
            .navigationTitle("Bibles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("bibles.done")
                }
            }
            .task {
                await library.refreshCatalog()
                hasLoaded = true
            }
            .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let removing { library.remove(removing) }
                }
            } message: {
                Text("Your highlights and notes stay. You can download it again any time.")
            }
        }
    }

    private func row(_ translation: Translation) -> some View {
        HStack(spacing: 14) {
            Text(translation.abbreviation)
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(translation.name).foregroundStyle(palette.text)
                Text(library.isBundled(translation) ? "Included" : "Downloaded")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if library.downloading.contains(translation.id) {
                ProgressView().accessibilityLabel("Updating")
            } else if translation == library.currentTranslation {
                Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityLabel("Current translation")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { reader.switchTranslation(to: translation) }
        .swipeActions {
            if library.isRemovable(translation) {
                Button("Remove", role: .destructive) { removing = translation }
            }
        }
        .contextMenu {
            if library.isRemovable(translation) {
                Button("Remove from This Device", systemImage: "trash", role: .destructive) { removing = translation }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bibles.installed.\(translation.id)")
    }

    private func downloadRow(_ item: DownloadableTranslation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(item.id)
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).foregroundStyle(palette.text)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.footnote).foregroundStyle(palette.secondaryText)
                }
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.fileBytes), countStyle: .file)) · \(item.license)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if library.downloading.contains(item.id) {
                ProgressView().accessibilityLabel("Downloading")
            } else {
                Button {
                    Task { await library.download(item) }
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download \(item.name)")
                .accessibilityIdentifier("bibles.download.\(item.id)")
            }
        }
    }
}
