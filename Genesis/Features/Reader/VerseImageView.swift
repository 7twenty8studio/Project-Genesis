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
            case .automatic: String(localized: "Auto", comment: "Verse image text color: follows the background")
            case .ink: String(localized: "Ink", comment: "Verse image text color")
            case .white: String(localized: "White", comment: "Verse image text color")
            case .cream: String(localized: "Cream", comment: "Verse image text color")
            case .gold: String(localized: "Gold", comment: "Verse image text color")
            case .navy: String(localized: "Navy", comment: "Verse image text color")
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
    case square, story, lockScreen

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: String(localized: "Square", comment: "Verse image shape")
        case .story: String(localized: "Story", comment: "Verse image shape: tall, for stories")
        case .lockScreen: String(localized: "Lock Screen", comment: "Verse image shape: a wallpaper for the iPhone's Lock Screen")
        }
    }

    /// Pixels (rendered at scale 1).
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .story: CGSize(width: 1080, height: 1920)
        // An iPhone screen (19.5:9, the Pro Max's pixels), so it fills the
        // Lock Screen of any recent iPhone without stretching.
        case .lockScreen: CGSize(width: 1290, height: 2796)
        }
    }

    /// Room kept clear around the words: on the Lock Screen, the date and
    /// clock above and the flashlight and camera buttons below.
    var textPadding: (top: CGFloat, bottom: CGFloat) {
        switch self {
        case .square: (100, 100)
        case .story: (260, 260)
        case .lockScreen: (size.height * 0.37, size.height * 0.16)
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
    @State private var saveOutcome: PhotoLibrarySaver.Outcome?
    @State private var liveProgress: Double?
    @State private var liveSaved = false
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements
    @Environment(BibleLibrary.self) private var library
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let size = shape.size
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    canvas
                        .frame(width: size.width, height: size.height)
                        // Where the Lock Screen's clock and buttons will be
                        // (only in the preview, never in the image).
                        .overlay {
                            if shape == .lockScreen { LockScreenGuide(size: size) }
                        }
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 18 * scale * 4, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preview: \(card.reference)")
                }
                .padding(.horizontal, 20)

                saveRow

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
                                    .accessibilityLabel("Center")
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
            .onChange(of: shape) { _, new in
                saveOutcome = nil
                // A wallpaper reads best centered under the clock.
                if new == .lockScreen { options.centered = true }
            }
            .onChange(of: rendered) {
                saveOutcome = nil
                liveSaved = false
            }
            .premiumSheet($premium)
            .alert("Versely can't save to Photos", isPresented: Binding(
                get: { saveOutcome == .notAllowed },
                set: { if !$0 { saveOutcome = nil } }
            )) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To save images, allow Versely to add photos in Settings.")
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var canvas: some View {
        VerseImageCanvas(card: card, style: style, shape: shape, options: options, photo: photo, currentTheme: currentTheme)
    }

    // MARK: Save and share

    private var saveRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await saveToPhotos() }
            } label: {
                Label(saveTitle, systemImage: saveOutcome == .saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(rendered == nil || saving)
            .accessibilityIdentifier("verseImage.save")
            if InstagramStories.isAvailable {
                Button {
                    if let rendered { InstagramStories.share(rendered) }
                } label: {
                    Label("Instagram Stories", systemImage: "camera.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(rendered == nil)
                .accessibilityIdentifier("verseImage.instagram")
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            if offersLive && saveOutcome != .saved {
                liveButton
                    .offset(y: 40)
            }
        }
        .padding(.bottom, offersLive && saveOutcome != .saved ? 36 : 0)
        .overlay(alignment: .bottom) {
            if saveOutcome == .saved && shape == .lockScreen {
                Text("Saved. To use it, open Settings › Wallpaper and add it from Photos.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .offset(y: 30)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, saveOutcome == .saved && shape == .lockScreen ? 24 : 0)
        .sensoryFeedback(.success, trigger: saveOutcome) { _, now in now == .saved }
    }

    /// A Live wallpaper: the Lock Screen shape with a season to move.
    /// Premium, and never with a YouVersion Bible's text (no Premium
    /// feature shows it).
    private var offersLive: Bool {
        shape == .lockScreen && style.season != nil && !library.currentTranslation.isYouVersion
    }

    private var liveButton: some View {
        Button {
            guard entitlements.allows(.premiumThemes) else {
                premium = .premiumThemes
                return
            }
            Task { await saveLive() }
        } label: {
            HStack(spacing: 6) {
                if let liveProgress {
                    ProgressView(value: liveProgress)
                        .frame(width: 60)
                    Text("Making your Live wallpaper…")
                } else {
                    Image(systemName: liveSaved ? "checkmark.circle.fill" : "livephoto")
                    Text(liveSaved ? String(localized: "Live wallpaper saved to Photos") : String(localized: "Save as Live Wallpaper"))
                    if !entitlements.allows(.premiumThemes) { PremiumBadge() }
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
        .disabled(liveProgress != nil)
        .accessibilityIdentifier("verseImage.live")
    }

    private func saveLive() async {
        liveSaved = false
        liveProgress = 0
        defer { liveProgress = nil }
        do {
            try await LiveWallpaperMaker.save(card: card, style: style, options: options, currentTheme: currentTheme) { value in
                liveProgress = value
            }
            withAnimation(Motion.easeOut(0.2)) { liveSaved = true }
        } catch LiveWallpaperMaker.Failure.notAllowed {
            saveOutcome = .notAllowed
        } catch {
            saveOutcome = .failed
        }
    }

    private var saveTitle: String {
        switch saveOutcome {
        case .saved: String(localized: "Saved to Photos")
        case .failed: String(localized: "Couldn't Save. Try Again")
        default: String(localized: "Save to Photos")
        }
    }

    private func saveToPhotos() async {
        guard let rendered else { return }
        saving = true
        let outcome = await PhotoLibrarySaver.save(rendered)
        saving = false
        withAnimation(Motion.easeOut(0.2)) { saveOutcome = outcome }
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
                if photo != nil {
                    // A photo already chosen: tap to use it again.
                    swatch(title: String(localized: "Your Photo", comment: "Verse image background: the photo already chosen"), selected: style == .photo, id: "verseImage.style.yourPhoto") {
                        if let photo { Image(uiImage: photo).resizable().scaledToFill().clipShape(Circle()) }
                    } action: {
                        style = .photo
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) { [palette] in
                    PhotoChoiceLabel(palette: palette)
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
        // Let the same photo be picked again later.
        photoItem = nil
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

/// The "Photo" choice under verse image backgrounds. Its own view, given the
/// colours, because the photo picker's label isn't main-actor isolated in
/// the newer SDK.
private struct PhotoChoiceLabel: View {
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .background(palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
            Text(VerseImageStyle.photo.title)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// The image itself, drawn at full size (1080 pixels wide).
struct VerseImageCanvas: View {
    let card: VerseCard
    let style: VerseImageStyle
    let shape: VerseImageShape
    let options: VerseImageOptions
    var photo: UIImage?
    let currentTheme: ReaderTheme
    /// The moment of the season's motion drawn (frames of a Live wallpaper
    /// move it on; a still image keeps the painted moment).
    var seasonTime: TimeInterval = SeasonalEffectView.paintedMoment

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
                SeasonalEffectView(season: season, stillTime: seasonTime)
                    .frame(width: shape.size.width / 2.5, height: shape.size.height / 2.5)
                    .scaleEffect(2.5)
                    .frame(width: shape.size.width, height: shape.size.height)
                    .opacity(0.9)
                    // On a wallpaper the leaves and snow keep to the sides,
                    // so the verse (and the clock above it) stay clear.
                    .mask {
                        if shape == .lockScreen {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.12), location: 0.24),
                                .init(color: .black.opacity(0.12), location: 0.76),
                                .init(color: .black, location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Rectangle()
                        }
                    }
            }
            VStack(alignment: alignment, spacing: 44) {
                Text(verbatim: "\u{201C}")
                    .font(options.font.font(size: 160))
                    .foregroundStyle(ink.opacity(0.45))
                    .frame(height: 70, alignment: .top)
                Text(ScriptureDirection.display(card.text))
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
                        Text(verbatim: "Versely")
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(ink.opacity(0.6))
                    }
                }
                if options.centered {
                    Text(verbatim: "Versely")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            .padding(.horizontal, shape == .lockScreen ? 120 : 96)
            .padding(.top, shape.textPadding.top)
            .padding(.bottom, shape.textPadding.bottom)
        }
        .frame(width: shape.size.width, height: shape.size.height)
        .clipped()
    }

    /// Larger for short verses, smaller for long passages, times the chosen size.
    private var textSize: CGFloat {
        let count = card.text.count
        let base: CGFloat = switch shape {
        case .square: 58
        case .story: 64
        case .lockScreen: 66
        }
        let fitted: CGFloat = switch count {
        case ..<120: base * 1.2
        case ..<260: base
        case ..<450: base * 0.8
        default: base * 0.66
        }
        return fitted * CGFloat(options.size)
    }
}

/// The Lock Screen's date, clock and buttons drawn faintly over the
/// wallpaper preview, so the verse can be placed clear of them. Never part
/// of the saved image.
private struct LockScreenGuide: View {
    let size: CGSize

    var body: some View {
        let now = Date.now
        VStack(spacing: 0) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 56, weight: .semibold))
                .padding(.top, size.height * 0.085)
            Text(now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: 300, weight: .bold, design: .rounded))
                .padding(.top, -20)
            Spacer()
            HStack {
                Image(systemName: "flashlight.off.fill")
                    .frame(width: 150, height: 150)
                    .background(.black.opacity(0.25), in: Circle())
                Spacer()
                Image(systemName: "camera.fill")
                    .frame(width: 150, height: 150)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .font(.system(size: 56))
            .padding(.horizontal, 130)
            .padding(.bottom, size.height * 0.05)
        }
        .foregroundStyle(.white.opacity(0.75))
        .shadow(color: .black.opacity(0.25), radius: 12)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
