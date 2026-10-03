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
    case paper, autumn, winter, spring, summer, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: String(localized: "Paper", comment: "Verse image background")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .night: String(localized: "Night", comment: "Verse image background")
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
        case .night: .midnight
        }
    }

    var season: Season? {
        switch self {
        case .autumn: .autumn
        case .winter: .winter
        case .spring: .spring
        case .summer: .summer
        case .paper, .night: nil
        }
    }
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

/// Make an image of the selected verses to share or save: typography in the
/// reader's font on textured paper, with the season's leaves, snow, blossom
/// or sunlight held still.
struct VerseImageView: View {
    let card: VerseCard

    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette
    @State private var style: VerseImageStyle = .paper
    @State private var shape: VerseImageShape = .square
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                GeometryReader { proxy in
                    let size = shape.size
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    VerseImageCanvas(card: card, style: style, shape: shape, font: settings.preferences.font, currentTheme: currentTheme)
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

                Picker("Shape", selection: $shape) {
                    ForEach(VerseImageShape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(VerseImageStyle.allCases) { item in
                            Button {
                                style = item
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(item.theme(reading: currentTheme).palette.background)
                                        .overlay(Circle().strokeBorder(style == item ? palette.accent : palette.separator, lineWidth: style == item ? 2.5 : 1))
                                        .frame(width: 44, height: 44)
                                    Text(item.title)
                                        .font(.caption2)
                                        .foregroundStyle(style == item ? palette.accent : palette.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("verseImage.style.\(item.rawValue)")
                            .accessibilityAddTraits(style == item ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                }
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
            .task(id: "\(style.rawValue)-\(shape.rawValue)") { render() }
        }
    }

    private var currentTheme: ReaderTheme {
        settings.preferences.theme.resolved(for: colorScheme)
    }

    private func render() {
        let renderer = ImageRenderer(content:
            VerseImageCanvas(card: card, style: style, shape: shape, font: settings.preferences.font, currentTheme: currentTheme)
                .frame(width: shape.size.width, height: shape.size.height)
        )
        renderer.scale = 1
        rendered = renderer.uiImage
    }
}

/// The image itself, drawn at full size (1080 pixels wide).
struct VerseImageCanvas: View {
    let card: VerseCard
    let style: VerseImageStyle
    let shape: VerseImageShape
    let font: ReaderFont
    let currentTheme: ReaderTheme

    var body: some View {
        let theme = style.theme(reading: currentTheme)
        let palette = theme.palette
        ZStack {
            Image(uiImage: PaperTexture.tile(for: theme))
                .resizable(resizingMode: .tile)
            if let season = style.season {
                // Drawn at phone size and enlarged, so leaves and snow keep
                // the size they have in the reader.
                SeasonalEffectView(season: season, stillTime: 7.3)
                    .frame(width: shape.size.width / 2.5, height: shape.size.height / 2.5)
                    .scaleEffect(2.5)
                    .frame(width: shape.size.width, height: shape.size.height)
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: 44) {
                Text(verbatim: "\u{201C}")
                    .font(font.font(size: 160))
                    .foregroundStyle(palette.accent.opacity(0.5))
                    .frame(height: 70, alignment: .top)
                Text(card.text)
                    .font(font.font(size: textSize))
                    .foregroundStyle(palette.text)
                    .lineSpacing(textSize * 0.32)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.reference)
                            .font(font.font(size: 40, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(card.translation)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Text(verbatim: "Genesis")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(palette.secondaryText.opacity(0.8))
                }
            }
            .padding(.horizontal, 96)
            .padding(.vertical, shape == .story ? 260 : 100)
        }
        .frame(width: shape.size.width, height: shape.size.height)
        .clipped()
    }

    /// Larger for short verses, smaller for long passages.
    private var textSize: CGFloat {
        let count = card.text.count
        let base: CGFloat = shape == .story ? 64 : 58
        switch count {
        case ..<120: return base * 1.2
        case ..<260: return base
        case ..<450: return base * 0.8
        default: return base * 0.66
        }
    }
}
