import PhotosUI
import SwiftUI

/// What goes on a verse image: verbatim Scripture from the database and its
/// reference.
struct VerseCard: Identifiable, Hashable, Sendable {
    let text: String
    let reference: String
    let translation: String
    var id: String { reference + translation }
}

/// A background for a verse image.
enum VerseImageStyle: String, CaseIterable, Identifiable {
    case paper, autumn, winter, spring, summer, night, photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: String(localized: "Paper", comment: "Verse image background")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .night: String(localized: "Night", comment: "Verse image background")
        case .photo: String(localized: "Photo", comment: "Verse image background: one of your photos")
        }
    }

    /// The theme whose paper and colours it uses.
    func theme(reading current: ReaderTheme) -> ReaderTheme {
        switch self {
        case .paper: current.isDark ? .paper : current
        case .autumn: .autumn
        case .winter: .winter
        case .spring: .spring
        case .summer: .summer
        case .night, .photo: .midnight
        }
    }

    var season: Season? {
        switch self {
        case .autumn: .autumn
        case .winter: .winter
        case .spring: .spring
        case .summer: .summer
        case .paper, .night, .photo: nil
        }
    }
}

/// How the words look on a verse image.
struct VerseImageOptions: Equatable {
    enum Ink: String, CaseIterable, Identifiable {
        case automatic, ink, white, cream, gold, navy
        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: String(localized: "Auto", comment: "Verse image text colour: follows the background")
            case .ink: String(localized: "Ink", comment: "Verse image text colour")
            case .white: String(localized: "White", comment: "Verse image text colour")
            case .cream: String(localized: "Cream", comment: "Verse image text colour")
            case .gold: String(localized: "Gold", comment: "Verse image text colour")
            case .navy: String(localized: "Navy", comment: "Verse image text colour")
            }
        }

        func color(theme: ReaderTheme) -> Color {
            switch self {
            case .automatic: theme.palette.text
            case .ink: Color(uiColor: UIColor(hex: 0x2B2A27))
            case .white: .white
            case .cream: Color(uiColor: UIColor(hex: 0xF4ECD8))
            case .gold: Color(uiColor: UIColor(hex: 0xC9A96E))
            case .navy: Color(uiColor: UIColor(hex: 0x1F2A44))
            }
        }
    }

    var font: ReaderFont
    var ink: Ink = .automatic
    /// Scales the text (0.7...1.4).
    var size: Double = 1
    var centered = false
}

enum VerseImageShape: String, CaseIterable, Identifiable {
    case square, story

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: String(localized: "Square", comment: "Verse image shape")
        case .story: String(localized: "Story", comment: "Verse image shape: tall, for stories")
        }
    }

    /// Pixels (rendered at scale 1).
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }
}

/// Make an image of the selected verses to share or save: the verse in the
/// reader's font (or another) on textured paper, a seasonal background or one
/// of your photos, with colour, size and alignment to taste.
struct VerseImageView: View {
    let card: VerseCard

    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette
    @State private var style: VerseImageStyle = .paper
    @State private var shape: VerseImageShape = .square
    @State private var options = VerseImageOptions(font: .newYork)
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var rendered: UIImage?
    @State private var didSetFont = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let size = shape.size
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    canvas
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 18 * scale * 4, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preview: \(card.reference)")
                }
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 16) {
                        Picker("Shape", selection: $shape) {
                            ForEach(VerseImageShape.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        backgrounds
                        fonts
                        inks

                        HStack(spacing: 12) {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $options.size, in: 0.7...1.4)
                                .tint(palette.accent)
                                .accessibilityLabel("Text size")
                                .accessibilityIdentifier("verseImage.size")
                            Image(systemName: "textformat.size.larger")
                            Divider().frame(height: 24)
                            Picker("Alignment", selection: $options.centered) {
                                Image(systemName: "text.alignleft").tag(false)
                                    .accessibilityLabel("Align left")
                                Image(systemName: "text.aligncenter").tag(true)
                                    .accessibilityLabel("Centre")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        .foregroundStyle(palette.secondaryText)
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 260)
            }
            .padding(.vertical, 12)
            .themedScreen()
            .navigationTitle("Verse Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let rendered {
                        ShareLink(
                            item: Image(uiImage: rendered),
                            preview: SharePreview(card.reference, image: Image(uiImage: rendered))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("verseImage.share")
                    } else {
                        ProgressView()
                    }
                }
            }
            .onAppear {
                guard !didSetFont else { return }
                didSetFont = true
                options.font = settings.preferences.font
            }
            .task(id: RenderKey(style: style, shape: shape, options: options, photo: photo.map { ObjectIdentifier($0) })) { render() }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var canvas: some View {
        VerseImageCanvas(card: card, style: style, shape: shape, options: options, photo: photo, currentTheme: currentTheme)
    }

    // MARK: Controls

    private var backgrounds: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(VerseImageStyle.allCases.filter { $0 != .photo }) { item in
                    swatch(title: item.title, selected: style == item, id: "verseImage.style.\(item.rawValue)") {
                        Circle().fill(item.theme(reading: currentTheme).palette.background)
                    } action: {
                        style = item
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: 6) {
                        Group {
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title3)
                                    .foregroundStyle(palette.accent)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(palette.surface)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(style == .photo ? palette.accent : palette.separator, lineWidth: style == .photo ? 2.5 : 1))
                        Text(VerseImageStyle.photo.title)
                            .font(.caption2)
                            .foregroundStyle(style == .photo ? palette.accent : palette.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a photo")
                .accessibilityIdentifier("verseImage.style.photo")
            }
        }
    }

    private var fonts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReaderFont.allCases) { font in
                    let selected = options.font == font
                    Button {
                        options.font = font
                    } label: {
                        Text("Aa")
                            .font(font.font(size: 20))
                            .frame(width: 52, height: 40)
                            .foregroundStyle(selected ? palette.background : palette.text)
                            .background(selected ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(font.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("verseImage.font.\(font.rawValue)")
                }
            }
        }
    }

    private var inks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(VerseImageOptions.Ink.allCases) { ink in
                    swatch(title: ink.title, selected: options.ink == ink, id: "verseImage.ink.\(ink.rawValue)") {
                        ZStack {
                            Circle().fill(style.theme(reading: currentTheme).palette.background)
                            Text(verbatim: "A")
                                .font(.system(size: 20, weight: .semibold, design: .serif))
                                .foregroundStyle(ink.color(theme: style.theme(reading: currentTheme)))
                        }
                    } action: {
                        options.ink = ink
                    }
                }
            }
        }
    }

    private func swatch(title: String, selected: Bool, id: String, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                content()
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(selected ? palette.accent : palette.separator, lineWidth: selected ? 2.5 : 1))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(selected ? palette.accent : palette.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: Helpers

    private var currentTheme: ReaderTheme {
        settings.preferences.theme.resolved(for: colorScheme)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        photo = image.preparingThumbnail(of: CGSize(width: 2160, height: 2160)) ?? image
        style = .photo
        if options.ink == .automatic { options.ink = .white }
    }

    private func render() {
        let renderer = ImageRenderer(content: canvas.frame(width: shape.size.width, height: shape.size.height))
        renderer.scale = 1
        rendered = renderer.uiImage
    }
}

private struct RenderKey: Equatable {
    let style: VerseImageStyle
    let shape: VerseImageShape
    let options: VerseImageOptions
    let photo: ObjectIdentifier?
}

/// The image itself, drawn at full size (1080 pixels wide).
struct VerseImageCanvas: View {
    let card: VerseCard
    let style: VerseImageStyle
    let shape: VerseImageShape
    let options: VerseImageOptions
    var photo: UIImage?
    let currentTheme: ReaderTheme

    var body: some View {
        let theme = style.theme(reading: currentTheme)
        let palette = theme.palette
        let ink = options.ink.color(theme: theme)
        let alignment: HorizontalAlignment = options.centered ? .center : .leading
        ZStack {
            if style == .photo, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: shape.size.width, height: shape.size.height)
                    .clipped()
                // A soft scrim so the words stay readable on any photo.
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            } else {
                Image(uiImage: PaperTexture.tile(for: theme))
                    .resizable(resizingMode: .tile)
            }
            if let season = style.season {
                // Drawn at phone size and enlarged, so leaves and snow keep
                // the size they have in the reader.
                SeasonalEffectView(season: season, stillTime: 7.3)
                    .frame(width: shape.size.width / 2.5, height: shape.size.height / 2.5)
                    .scaleEffect(2.5)
                    .frame(width: shape.size.width, height: shape.size.height)
                    .opacity(0.9)
            }
            VStack(alignment: alignment, spacing: 44) {
                Text(verbatim: "\u{201C}")
                    .font(options.font.font(size: 160))
                    .foregroundStyle(ink.opacity(0.45))
                    .frame(height: 70, alignment: .top)
                Text(card.text)
                    .font(options.font.font(size: textSize))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(options.centered ? .center : .leading)
                    .lineSpacing(textSize * 0.32)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: options.centered ? .center : .topLeading)
                HStack(alignment: .lastTextBaseline) {
                    if options.centered { Spacer() }
                    VStack(alignment: alignment, spacing: 6) {
                        Text(card.reference)
                            .font(options.font.font(size: 40, weight: .semibold))
                            .foregroundStyle(options.ink == .automatic ? palette.accent : ink)
                        Text(card.translation)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(ink.opacity(0.7))
                    }
                    Spacer()
                    if !options.centered {
                        Text(verbatim: "Genesis")
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(ink.opacity(0.6))
                    }
                }
                if options.centered {
                    Text(verbatim: "Genesis")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            .padding(.horizontal, 96)
            .padding(.vertical, shape == .story ? 260 : 100)
        }
        .frame(width: shape.size.width, height: shape.size.height)
        .clipped()
    }

    /// Larger for short verses, smaller for long passages, times the chosen size.
    private var textSize: CGFloat {
        let count = card.text.count
        let base: CGFloat = shape == .story ? 64 : 58
        let fitted: CGFloat = switch count {
        case ..<120: base * 1.2
        case ..<260: base
        case ..<450: base * 0.8
        default: base * 0.66
        }
        return fitted * CGFloat(options.size)
    }
}
