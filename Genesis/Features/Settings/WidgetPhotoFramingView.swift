import SwiftUI

/// Settings › Widget Photo › Adjust: the person drags and pinches their
/// photo inside each widget size (small, medium, large), with the verse
/// laid over it as the widget shows it. Each size keeps its own framing
/// (`PhotoFraming`); Done writes the cut photos for the widget.
struct WidgetPhotoFramingView: View {
    let photo: UIImage
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shape: WidgetArtShape = .medium
    @State private var framings: [WidgetArtShape: PhotoFraming] = Dictionary(
        uniqueKeysWithValues: WidgetArtShape.allCases.map { ($0, WidgetArtWriter.framing(for: $0)) }
    )
    @State private var gestureStart: PhotoFraming?
    @State private var saving = false

    /// The photo's size in pixels, the space every framing is measured in.
    private var pixels: CGSize {
        CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Widget Size", selection: $shape) {
                    Text("Small").tag(WidgetArtShape.small)
                    Text("Medium").tag(WidgetArtShape.medium)
                    Text("Large").tag(WidgetArtShape.large)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("widgetPhoto.size")

                GeometryReader { proxy in
                    frame(in: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text("Drag to move the photo and pinch to zoom. Each widget size keeps its own framing.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)

                Button("Reset") {
                    withAnimation(reduceMotion ? nil : Motion.easeOut(0.2)) {
                        framings[shape] = PhotoFraming()
                    }
                }
                .disabled(framings[shape] == PhotoFraming())
                .accessibilityIdentifier("widgetPhoto.reset")
            }
            .padding(20)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(saving)
                        .accessibilityIdentifier("widgetPhoto.done")
                }
            }
        }
    }

    // MARK: The frame

    /// The widget's shape in points (an iPhone's widget sizes), scaled
    /// down if the screen is narrower.
    private func frameSize(in available: CGSize) -> CGSize {
        let base: CGSize = switch shape {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
        let scale = min(1, available.width / base.width, available.height / base.height)
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    private func frame(in available: CGSize) -> some View {
        let size = frameSize(in: available)
        let aspect = size.width / size.height
        let framing = framings[shape] ?? PhotoFraming()
        let crop = framing.crop(imageSize: pixels, aspect: aspect)
        let scale = crop.width > 0 ? size.width / crop.width : 1
        return ZStack(alignment: .topLeading) {
            Image(uiImage: photo)
                .resizable()
                .frame(width: pixels.width * scale, height: pixels.height * scale)
                .offset(x: -crop.minX * scale, y: -crop.minY * scale)
            // The widget's shade and words, so the photo is placed around them.
            LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.42), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            sampleVerse
                .padding(16)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .gesture(
            SimultaneousGesture(DragGesture(minimumDistance: 2), MagnifyGesture())
                .onChanged { value in
                    // Both measured from where the gesture began.
                    let start = gestureStart ?? framing
                    gestureStart = start
                    var moved = start
                    if let magnification = value.second?.magnification {
                        moved = moved.zoomed(by: magnification, imageSize: pixels, aspect: aspect)
                    }
                    if let translation = value.first?.translation {
                        moved = moved.panned(by: translation, frameSize: size, imageSize: pixels)
                    }
                    framings[shape] = moved
                }
                .onEnded { _ in gestureStart = nil }
        )
        .onTapGesture(count: 2) {
            // Double tap: back to the whole photo.
            withAnimation(reduceMotion ? nil : Motion.easeOut(0.2)) {
                framings[shape] = PhotoFraming()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your photo in the widget"))
        .accessibilityHint(Text("Drag to move the photo and pinch to zoom."))
        .accessibilityIdentifier("widgetPhoto.frame")
    }

    /// Today's verse as the widget has it (verbatim), if the app has
    /// written it yet; otherwise just the heading.
    private var sampleVerse: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verse of the Day")
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .kerning(1)
                .foregroundStyle(Color(uiColor: UIColor(hex: 0xE8D3A2)))
            if let passage = WidgetSnapshot.load()?.dailyPassage(on: .now) {
                Text(ScriptureDirection.display(passage.text))
                    .font(.system(shape == .small ? .footnote : .body, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(shape == .large ? 8 : 3)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                Spacer(minLength: 0)
                Text(verbatim: passage.reference + " \u{00B7} " + passage.translation)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .allowsHitTesting(false)
    }

    private func save() {
        saving = true
        WidgetArtWriter.saveFramings(framings, photo: photo)
        onSave()
        dismiss()
    }
}
