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

    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var moving: Bool {
        animates && !reduceMotion && !lowPower && scenePhase == .active && visible
    }

    var body: some View {
        let art = scene.artFrame(in: size, safeBottom: safeBottom)
        ZStack(alignment: .topLeading) {
            // The picture can be wider than the screen: an overlay, so it
            // never changes the scene's own size.
            Color(uiColor: UIColor(hex: scene.fillHex))
                .overlay(alignment: .topLeading) {
                    if scene == .forest {
                        // The boughs sway, so the Forest's picture moves too.
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                            let time = moving ? timeline.date.timeIntervalSinceReferenceDate : ThemeScene.stillTime
                            SwayingForest(tiles: scene.tiles(in: size, safeBottom: safeBottom), name: scene.artName, time: time)
                        }
                    } else {
                        ForEach(Array(scene.tiles(in: size, safeBottom: safeBottom).enumerated()), id: \.offset) { _, tile in
                            SceneArtImage(name: scene.artName, tile: tile)
                        }
                    }
                }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                let time = moving ? timeline.date.timeIntervalSinceReferenceDate : ThemeScene.stillTime
                SceneMotionLayer(scene: scene, size: size, art: art, textBottom: textBottom, time: time)
            }
            SceneShadeView(shade: scene.shade)
            if scene == .hearth {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                    let time = moving ? timeline.date.timeIntervalSinceReferenceDate : ThemeScene.stillTime
                    HearthEmberLayer(art: art, textBottom: textBottom, time: time)
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

/// The Forest's picture with its boughs swaying (`ForestSway`): the whole
/// picture still, then the canopy without its trunks in moving bands, the
/// trunks still over it, and the boughs in front of them moving again.
private struct SwayingForest: View {
    let tiles: [SceneTile]
    let name: String
    let time: Double

    var body: some View {
        Canvas { context, size in
            let image = context.resolve(Image(name))
            let canopy = context.resolve(Image(ForestSway.canopyName))
            let trunks = context.resolve(Image(ForestSway.trunksName))
            let front = context.resolve(Image(ForestSway.frontName))
            for tile in tiles {
                let frame = tile.frame
                var art = context
                if tile.mirrored {
                    art.translateBy(x: frame.midX, y: 0)
                    art.scaleBy(x: -1, y: 1)
                    art.translateBy(x: -frame.midX, y: 0)
                }
                art.draw(image, in: frame)
                let base = art
                let canopyFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * ForestSway.canopy)
                guard canopyFrame.maxY > 0 else { continue }
                // Moving bands (a hair of overlap hides seams).
                let band = canopyFrame.height / CGFloat(ForestSway.bands)
                func drawBands(_ layer: GraphicsContext.ResolvedImage) {
                    for index in 0..<ForestSway.bands {
                        let top = canopyFrame.minY + CGFloat(index) * band
                        guard top + band > 0, top < size.height else { continue }
                        let share = (CGFloat(index) + 0.5) / CGFloat(ForestSway.bands) * ForestSway.canopy
                        let shift = ForestSway.offset(atShare: share, time: time) * (tile.mirrored ? -1 : 1)
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
    }
}

/// What moves under the shade: the Forest's mist, the Ocean's swells and
/// the glow over Hearth's coals.
private struct SceneMotionLayer: View {
    let scene: ThemeScene
    let size: CGSize
    let art: CGRect
    let textBottom: CGFloat
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
            Canvas { context, _ in
                let coals = CGPoint(x: art.minX + art.width * ThemeScene.Hearth.coals.x, y: art.minY + art.height * ThemeScene.Hearth.coals.y)
                let radius = art.height * 0.2
                let strength = 0.07 + 0.06 * HearthSparks.glow(at: time)
                let ember = Color(red: 1, green: 0.6, blue: 0.3)
                context.blendMode = .plusLighter
                context.fill(
                    Path(ellipseIn: CGRect(x: coals.x - radius, y: coals.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [ember.opacity(strength), ember.opacity(0)]),
                        center: coals, startRadius: 0, endRadius: radius
                    )
                )
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

/// Hearth's sparks, over the shade so they stay bright, gone before the text.
private struct HearthEmberLayer: View {
    let art: CGRect
    let textBottom: CGFloat
    let time: Double

    var body: some View {
        Canvas { context, _ in
            let source = CGPoint(x: art.minX + art.width * ThemeScene.Hearth.coals.x, y: art.minY + art.height * ThemeScene.Hearth.coals.y)
            let width = art.width * ThemeScene.Hearth.coalsWidth
            let ceiling = textBottom + 14
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
