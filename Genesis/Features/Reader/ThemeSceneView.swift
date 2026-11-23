import SwiftUI

/// The scene behind the words in Forest, Ocean and Hearth (`ThemeScene`):
/// the illustration, its one moving layer (mist, swells or embers) and the
/// soft shade where the text sits. It's under the text and controls, ignores
/// touches and is hidden from VoiceOver.
///
/// Motion runs only while it can be seen: with Gentle Motion on, Reduce
/// Motion off, outside Low Power Mode, with the app active and the reader
/// on screen. Otherwise it shows the composed still (`ThemeScene.stillTime`).
struct ThemeSceneView: View {
    let scene: ThemeScene
    let size: CGSize
    let safeBottom: CGFloat
    /// The bottom of the text (embers fade out before it).
    let textBottom: CGFloat
    /// Gentle Motion is on.
    var animates: Bool
    var reduceMotion: Bool
    var lowPower: Bool
    /// The moment drawn when it isn't moving (a still taken mid-motion for
    /// a page curl); the composed `ThemeScene.stillTime` otherwise.
    var frozenTime: Double? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var moving: Bool {
        animates && !reduceMotion && !lowPower && scenePhase == .active && visible
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The picture can be wider than the screen: an overlay, so it
            // never changes the scene's own size.
            Color(uiColor: UIColor(hex: scene.fillHex))
                .overlay(alignment: .topLeading) {
                    if scene == .forest {
                        // The boughs sway, so the Forest's picture moves too.
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                            let time = moving ? timeline.date.timeIntervalSinceReferenceDate : (frozenTime ?? ThemeScene.stillTime)
                            SwayingForest(size: size, time: time)
                        }
                    } else if let name = scene.artName {
                        ForEach(Array(scene.tiles(in: size, safeBottom: safeBottom).enumerated()), id: \.offset) { _, tile in
                            SceneArtImage(name: name, tile: tile)
                        }
                        if scene == .ocean {
                            OceanSky(name: name, size: size)
                        }
                    }
                }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                let time = moving ? timeline.date.timeIntervalSinceReferenceDate : (frozenTime ?? ThemeScene.stillTime)
                SceneMotionLayer(scene: scene, size: size, time: time)
            }
            SceneShadeView(shade: scene.shade)
            if scene == .hearth {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                    let time = moving ? timeline.date.timeIntervalSinceReferenceDate : (frozenTime ?? ThemeScene.stillTime)
                    HearthEmberLayer(time: time)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

/// One copy of the picture, mirrored where it repeats.
private struct SceneArtImage: View {
    let name: String
    let tile: SceneTile

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaleEffect(x: tile.mirrored ? -1 : 1, y: 1)
            .frame(width: tile.frame.width, height: tile.frame.height)
            .offset(x: tile.frame.minX, y: tile.frame.minY)
    }
}

/// The Ocean's clouds drawn again, raised (`ThemeScene.oceanSky`) and
/// fading out in the plain sky below them, so they sit higher than the
/// water does.
private struct OceanSky: View {
    let name: String
    let size: CGSize

    var body: some View {
        let sky = ThemeScene.oceanSky(in: size)
        let art = ThemeScene.ocean.artFrame(in: size, safeBottom: 0)
        let fadeTop = (art.minY + art.height * ThemeScene.skyFade.lowerBound) / size.height
        let fadeBottom = (art.minY + art.height * ThemeScene.skyFade.upperBound) / size.height
        ZStack(alignment: .topLeading) {
            ForEach(Array(ThemeScene.tiles(of: sky, across: size.width).enumerated()), id: \.offset) { _, tile in
                SceneArtImage(name: name, tile: tile)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: fadeTop),
                .init(color: .black.opacity(0), location: fadeBottom),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The Forest's picture with its boughs swaying (`ForestSway`): the whole
/// picture still, then the canopy without its trunks in moving bands, the
/// trunks still over it, and the boughs in front of them moving again. On
/// an area wider than tall, the wide picture held to both edges
/// (`ForestWide`); otherwise the tall one, mirrored where it repeats.
private struct SwayingForest: View {
    let size: CGSize
    let time: Double

    var body: some View {
        Canvas { context, size in
            if ForestWide.uses(size) {
                let layers = ForestLayers(context: context, name: ForestWide.name, canopy: ForestWide.canopyName,
                                          trunks: ForestWide.trunksName, front: ForestWide.frontName, share: ForestWide.canopy)
                let copies = ForestWide.copies(in: size)
                let blend = ForestWide.blend(in: size)
                layers.draw(in: context, frame: copies.left, mirrored: false, time: time, height: size.height)
                // The right copy fades in across the clearing in the middle.
                context.drawLayer { layer in
                    layers.draw(in: layer, frame: copies.right, mirrored: false, time: time, height: size.height)
                    layer.blendMode = .destinationIn
                    layer.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .black.opacity(0), location: blend.lowerBound / size.width),
                                .init(color: .black, location: blend.upperBound / size.width),
                            ]),
                            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
                        )
                    )
                }
            } else {
                let layers = ForestLayers(context: context, name: "ThemeSceneForest", canopy: ForestSway.canopyName,
                                          trunks: ForestSway.trunksName, front: ForestSway.frontName, share: ForestSway.canopy)
                for tile in ThemeScene.forest.tiles(in: size, safeBottom: 0) {
                    layers.draw(in: context, frame: tile.frame, mirrored: tile.mirrored, time: time, height: size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One forest picture and its three canopy layers, ready to draw.
private struct ForestLayers {
    let image: GraphicsContext.ResolvedImage
    let canopy: GraphicsContext.ResolvedImage
    let trunks: GraphicsContext.ResolvedImage
    let front: GraphicsContext.ResolvedImage
    /// The canopy layers' share of the picture's height.
    let share: CGFloat

    init(context: GraphicsContext, name: String, canopy: String, trunks: String, front: String, share: CGFloat) {
        image = context.resolve(Image(name))
        self.canopy = context.resolve(Image(canopy))
        self.trunks = context.resolve(Image(trunks))
        self.front = context.resolve(Image(front))
        self.share = share
    }

    /// Draws one copy of the picture at `frame` (mirrored where it repeats)
    /// with its boughs moved for `time`; `height` is the area's height.
    func draw(in context: GraphicsContext, frame: CGRect, mirrored: Bool, time: Double, height: CGFloat) {
        var art = context
        if mirrored {
            art.translateBy(x: frame.midX, y: 0)
            art.scaleBy(x: -1, y: 1)
            art.translateBy(x: -frame.midX, y: 0)
        }
        art.draw(image, in: frame)
        let canopyFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * share)
        guard canopyFrame.maxY > 0 else { return }
        // Moving bands (a hair of overlap hides seams).
        let band = canopyFrame.height / CGFloat(ForestSway.bands)
        let base = art
        func drawBands(_ layer: GraphicsContext.ResolvedImage) {
            for index in 0..<ForestSway.bands {
                let top = canopyFrame.minY + CGFloat(index) * band
                guard top + band > 0, top < height else { continue }
                let bandShare = (CGFloat(index) + 0.5) / CGFloat(ForestSway.bands) * ForestSway.canopy
                let shift = ForestSway.offset(atShare: bandShare, time: time) * (mirrored ? -1 : 1)
                var strip = base
                strip.clip(to: Path(CGRect(x: frame.minX - 20, y: top, width: frame.width + 40, height: band + 0.5)))
                strip.draw(layer, in: canopyFrame.offsetBy(dx: shift, dy: 0))
            }
        }
        drawBands(canopy)
        art.draw(trunks, in: canopyFrame)
        drawBands(front)
    }
}

/// What moves under the shade: the Forest's mist, the Ocean's swells and
/// Hearth's glow rising from the foot of the screen.
private struct SceneMotionLayer: View {
    let scene: ThemeScene
    let size: CGSize
    let time: Double

    var body: some View {
        switch scene {
        case .forest:
            Canvas { context, size in
                for layer in ForestMist.layers {
                    for puff in layer.puffs {
                        let state = ForestMist.state(of: puff, in: layer, at: time, size: size)
                        let mist = Color(red: 0.87, green: 0.92, blue: 0.86)
                        // A unit circle stretched to the puff, so it's soft all round.
                        var puffContext = context
                        puffContext.translateBy(x: state.center.x, y: state.center.y)
                        puffContext.scaleBy(x: state.radii.width, y: state.radii.height)
                        puffContext.fill(
                            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                            with: .radialGradient(
                                Gradient(colors: [mist.opacity(state.opacity), mist.opacity(state.opacity * 0.45), mist.opacity(0)]),
                                center: .zero, startRadius: 0, endRadius: 1
                            )
                        )
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        case .ocean:
            Color.clear
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    OceanSwellLayer(near: false, size: size, time: time)
                    OceanSwellLayer(near: true, size: size, time: time)
                }
        case .hearth:
            Canvas { context, size in
                // The fire is just below the screen: its glow rises from the
                // whole foot, breathing, brighter patches wandering along it.
                let strength = HearthGlow.strength(at: time)
                let top = size.height * (1 - HearthGlow.height)
                let amber = Color(red: 0.78, green: 0.45, blue: 0.23)
                let flame = Color(red: 1, green: 0.66, blue: 0.34)
                context.fill(
                    Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: amber.opacity(0), location: 0),
                            .init(color: amber.opacity(0.17 * strength), location: 0.55),
                            .init(color: amber.opacity(0.5 * strength), location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.blendMode = .plusLighter
                for patch in HearthGlow.patches(at: time) {
                    let center = CGPoint(x: size.width * patch.x, y: size.height + size.height * 0.03)
                    let radii = CGSize(width: size.width * 0.42, height: size.height * 0.16)
                    var glow = context
                    glow.translateBy(x: center.x, y: center.y)
                    glow.scaleBy(x: radii.width, y: radii.height)
                    glow.fill(
                        Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                        with: .radialGradient(
                            Gradient(colors: [flame.opacity(0.32 * strength * patch.strength), flame.opacity(0)]),
                            center: .zero, startRadius: 0, endRadius: 1
                        )
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// One of the Ocean's two swell layers, repeated (mirrored) across when the
/// screen is wider than one copy.
private struct OceanSwellLayer: View {
    let near: Bool
    let size: CGSize
    let time: Double

    var body: some View {
        let frame = OceanSwells.frame(near: near, in: size)
        let period = OceanSwells.period(in: size)
        let offset = OceanSwells.offset(near: near, at: time)
        let copies = ThemeScene.tiles(of: CGRect(x: frame.minX + (frame.width - period) / 2, y: frame.minY, width: period, height: frame.height), across: size.width)
        ForEach(Array(copies.enumerated()), id: \.offset) { _, copy in
            Image(near ? OceanSwells.nearName : OceanSwells.farName)
                .resizable()
                .interpolation(.high)
                .scaleEffect(x: copy.mirrored ? -1 : 1, y: 1)
                .frame(width: frame.width, height: frame.height)
                .offset(x: copy.frame.minX - (frame.width - period) / 2 + offset.width, y: frame.minY - offset.height)
        }
    }
}

/// Hearth's sparks, over the shade so they stay bright: rising from all
/// along the foot of the screen as high as the glow reaches, fading as
/// they climb (still under the words).
private struct HearthEmberLayer: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            let source = CGPoint(x: size.width / 2, y: size.height + 4)
            let width = size.width * HearthGlow.emberWidth
            let ceiling = size.height * (1 - HearthGlow.height)
            context.blendMode = .plusLighter
            for (index, spark) in HearthSparks.sparks.enumerated() {
                guard let state = HearthSparks.state(of: spark, index: index, at: time, source: source, width: width, ceiling: ceiling),
                      state.opacity > 0.01 else { continue }
                let glow = state.radius * 3.5
                context.fill(
                    Path(ellipseIn: CGRect(x: state.point.x - glow, y: state.point.y - glow, width: glow * 2, height: glow * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(state.opacity * 0.35), .clear]),
                        center: state.point, startRadius: 0, endRadius: glow
                    )
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: state.point.x - state.radius, y: state.point.y - state.radius, width: state.radius * 2, height: state.radius * 2)),
                    with: .color(Color(red: 1, green: 0.8, blue: 0.5).opacity(state.opacity))
                )
            }
        }
    }
}

/// The soft shade behind the words.
private struct SceneShadeView: View {
    let shade: SceneShade

    var body: some View {
        Canvas { context, size in
            let color = Color(uiColor: UIColor(hex: shade.hex))
            let stops = shade.stops.map { Gradient.Stop(color: color.opacity($0.opacity), location: $0.location) }
            let center = CGPoint(x: size.width * shade.center.x, y: size.height * shade.center.y)
            // A unit circle, stretched to the ellipse.
            var ellipse = context
            ellipse.translateBy(x: center.x, y: center.y)
            ellipse.scaleBy(x: size.width * shade.radii.width, y: size.height * shade.radii.height)
            // Beyond the ellipse, its edge opacity.
            if let edge = shade.stops.last?.opacity, edge > 0 {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(edge)))
                ellipse.blendMode = .copy
            }
            ellipse.fill(
                Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: 1)
            )
        }
    }
}

/// The scene as a still picture (with its shade), for pages that curl: a
/// curl needs opaque pages, so while a page turns each page carries its
/// part of the scene instead of showing the live one through clear paper.
/// Taken at the moment the turn starts while the scene moves; otherwise at
/// `ThemeScene.stillTime`, drawn once per scene and size.
@MainActor
enum SceneStill {
    private static var cached: (key: String, image: UIImage)?

    /// The still for `size` (the reading area by default), at `time` if
    /// given (not cached), else at `ThemeScene.stillTime`.
    static func image(scene: ThemeScene, layout: ReaderLayout, size: CGSize? = nil, time: Double? = nil) -> UIImage? {
        let size = size ?? layout.size
        guard size.width > 1, size.height > 1 else { return nil }
        let textBottom = layout.size.height - layout.textInsets.bottom
        let key = "\(scene.rawValue)-\(Int(size.width))x\(Int(size.height))-\(Int(textBottom))"
        if time == nil, let cached, cached.key == key { return cached.image }
        let renderer = ImageRenderer(content: ThemeSceneView(
            scene: scene,
            size: size,
            safeBottom: layout.safeArea.bottom,
            textBottom: textBottom,
            animates: false,
            reduceMotion: true,
            lowPower: true,
            frozenTime: time
        ))
        renderer.scale = UITraitCollection.current.displayScale
        guard let image = renderer.uiImage else { return nil }
        if time == nil { cached = (key, image) }
        return image
    }
}
