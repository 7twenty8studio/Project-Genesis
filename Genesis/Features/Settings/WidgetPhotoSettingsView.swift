import PhotosUI
import SwiftUI

/// Settings › Widget Photo (Premium): the photo the verse widget shows with
/// the Your Photo style (Widget Styles, or a widget's own Background). Kept in the App Group, made smaller
/// and without its metadata (`WidgetArtWriter.savePhoto`), and framed for
/// each widget size by dragging and pinching (`WidgetPhotoFramingView`).
struct WidgetPhotoSettingsView: View {
    @Environment(\.palette) private var palette
    @State private var photo: UIImage? = WidgetArtWriter.photo
    @State private var item: PhotosPickerItem?
    @State private var failed = false
    @State private var framing = false
    /// The medium widget's framed photo, for the preview.
    @State private var framed: UIImage? = Self.framedPreview()

    private static func framedPreview() -> UIImage? {
        WidgetArt.url(.photo, shape: .medium).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    let title = photo == nil ? String(localized: "Choose Photo") : String(localized: "Change Photo")
                    PhotosPicker(selection: $item, matching: .images) { [palette, title] in
                        Label(title, systemImage: "photo.badge.plus")
                            .foregroundStyle(palette.accent)
                    }
                    .accessibilityIdentifier("widgetPhoto.choose")
                    if photo != nil {
                        Button {
                            framing = true
                        } label: {
                            Label("Adjust Photo", systemImage: "crop")
                                .foregroundStyle(palette.accent)
                        }
                        .accessibilityIdentifier("widgetPhoto.adjust")
                        Button(role: .destructive) {
                            WidgetArtWriter.removePhoto()
                            withAnimation(Motion.easeOut(0.2)) {
                                photo = nil
                                framed = nil
                            }
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                        .accessibilityIdentifier("widgetPhoto.remove")
                    }
                } footer: {
                    Text("To use it, choose Your Photo in Settings › Widget Styles. The photo stays on this iPhone.")
                }
                .listRowBackground(palette.surface)
                .foregroundStyle(palette.text)
            }
        }
        .themedScreen()
        .navigationTitle("Widget Photo")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't use that photo", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: item) { _, new in
            Task { await load(new) }
        }
        .sheet(isPresented: $framing) {
            if let photo {
                WidgetPhotoFramingView(photo: photo) {
                    framed = Self.framedPreview()
                }
            }
        }
    }

    /// A medium widget with a sample verse, as it will look.
    private var preview: some View {
        ZStack(alignment: .topLeading) {
            if let shown = framed ?? photo {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
                LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.42), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            } else {
                palette.surface
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if photo != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verse of the Day")
                        .textCase(.uppercase)
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(Color(uiColor: UIColor(hex: 0xE8D3A2)))
                    // Today's verse as the widget has it (verbatim), if the
                    // app has written it yet.
                    if let passage = WidgetSnapshot.load()?.dailyPassage(on: .now) {
                        Text(passage.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        Spacer(minLength: 0)
                        Text(verbatim: passage.reference + " \u{00B7} " + passage.translation)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 338, height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photo == nil ? Text("No photo chosen") : Text("Preview of the verse widget with your photo"))
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { self.item = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            failed = true
            return
        }
        do {
            try WidgetArtWriter.savePhoto(image)
            withAnimation(Motion.easeOut(0.2)) {
                photo = WidgetArtWriter.photo
                framed = Self.framedPreview()
            }
            // Straight on to placing it.
            framing = true
        } catch {
            failed = true
        }
    }
}
