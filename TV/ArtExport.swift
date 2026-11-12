#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AquariumKit

/// Renders the app icon layers and Top Shelf images with the real art and renderers, so they look
/// like the tank. Debug builds only: launch with `-exportArt <directory>`; it writes PNGs there and
/// the app exits. The PNGs are then copied into `Assets.xcassets` by hand.
enum ArtExport {
    static func runIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "exportArt") else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scale in [1, 2] {
            let suffix = scale == 1 ? "" : "@2x"
            iconLayers(size: CGSize(width: 400, height: 240), scale: scale, into: dir, name: "icon", suffix: suffix)
            write(topShelf(size: CGSize(width: 1920, height: 720), scale: scale), to: dir, "topshelf\(suffix)")
            write(topShelf(size: CGSize(width: 2320, height: 720), scale: scale), to: dir, "topshelf-wide\(suffix)")
        }
        iconLayers(size: CGSize(width: 1280, height: 768), scale: 1, into: dir, name: "appstore", suffix: "")
        exit(0)
    }

    /// The Navy swatch fading to black: brighter than the default gradient, so the icon isn't a dark hole.
    private static let iconBackground = Background.gradient(top: RGB(r: 0.00, g: 0.10, b: 0.25), bottom: .black)

    /// One big fish, facing left, nearly the full height of the icon. Back: the sea and the water line,
    /// raised to the top edge. Middle: a few bubbles ahead of its nose. Front: the fish.
    private static func iconLayers(size: CGSize, scale: Int, into dir: URL, name: String, suffix: String) {
        let fishRows = 16
        write(render(size: size, scale: scale, rows: 26, background: iconBackground) { c in
            addEnvironment(c)
            for line in c.engine.entities(ofType: "waterline") { line.y -= 4 }
        }, to: dir, "\(name)-back\(suffix)")
        let fish = bigFish(cols: 0) // for its size only
        let fishX = { (cols: Int) in Double((cols - fish.width) / 2) }
        let fishY = Double(fishRows - fish.height - 1)
        write(render(size: size, scale: scale, rows: fishRows, background: nil) { c in
            let x = fishX(c.engine.cols)
            for (char, dx, dy) in [("o", -3.0, 3.0), (".", -5.0, 5.0), ("O", -2.0, 7.0)] {
                c.engine.add(Entity(
                    sprite: Sprite(shapes: [char]), x: x + dx, y: fishY + dy, defaultColor: CellColor(color: .cyan, bright: true)))
            }
        }, to: dir, "\(name)-middle\(suffix)")
        write(render(size: size, scale: scale, rows: fishRows, background: nil) { c in
            let f = bigFish(cols: c.engine.cols)
            f.x = fishX(c.engine.cols)
            f.y = fishY
            c.engine.add(f)
        }, to: dir, "\(name)-front\(suffix)")
    }

    /// The tank's second big fish facing left, with a fixed cyan body and yellow stripes (in the tank
    /// its colors are random).
    private static func bigFish(cols: Int) -> Entity {
        let mask = BigFishArt.twoMasks[1].replacingOccurrences(of: "1", with: "C").replacingOccurrences(of: "2", with: "Y")
        return Entity(
            sprite: Sprite(shapes: [BigFishArt.twoShapes[1]], masks: [mask], autoTransparent: true),
            defaultColor: CellColor(color: .yellow, bright: true))
    }

    /// A whole tank, seed 42, a few seconds in.
    private static func topShelf(size: CGSize, scale: Int) -> CGImage {
        render(size: size, scale: scale, rows: 24, background: AquariumSettings.defaultGradient) { c in
            addEnvironment(c)
            addCastle(c)
            addAllSeaweed(c)
            addAllFish(c)
            for _ in 0..<40 { c.engine.step() }
            tidyStill(c.engine)
        }
    }

    /// Tidies a still of the tank. Fish crossing the castle or each other read as a jumble, and fish
    /// by the castle crowd the right side, so each such fish moves to the first clear spot on the left
    /// half at the same height, clear of the left edge (the TV can crop the wide image there). Seaweed
    /// showing through the castle goes.
    private static func tidyStill(_ engine: Engine) {
        let castleLeft = Double(engine.cols - 32)
        for weed in engine.entities(ofType: "self") where weed.z == Depth.seaweed && weed.x + 2 > castleLeft {
            engine.remove(weed)
        }
        let fish = engine.entities(ofType: "fish")
        func clear(_ f: Entity, at x: Double) -> Bool {
            x + Double(f.width) <= castleLeft - 2 && fish.allSatisfy { o in
                o === f || x + Double(f.width) + 2 <= o.x || o.x + Double(o.width) + 2 <= x
                    || f.y + Double(f.height) <= o.y || o.y + Double(o.height) <= f.y
            }
        }
        for f in fish where !clear(f, at: f.x) {
            if let x = stride(from: Double(engine.cols) * 0.12, to: Double(engine.cols / 2), by: 2).first(where: { clear(f, at: $0) }) {
                f.x = x
            }
        }
    }

    /// Draws a grid `rows` tall filling `size`, with what `build` puts in a fresh engine.
    private static func render(
        size: CGSize, scale: Int, rows: Int, background: Background?, build: (SpawnContext) -> Void
    ) -> CGImage {
        let probe = GridRenderer(pointSize: 10, palette: .terminal)
        let renderer = GridRenderer(pointSize: 10 * size.height / (CGFloat(rows) * probe.cellSize.height), palette: .terminal)
        let layout = GridLayout.fit(viewSize: size, cellSize: renderer.cellSize)

        let engine = Engine(cols: layout.cols, rows: layout.rows, rng: RandomSource(seed: 42))
        build(SpawnContext(engine: engine, settings: .defaults))

        let ctx = CGContext(
            data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        if let background {
            let bg = BackgroundRenderer()
            let gridTop = layout.origin.y + CGFloat(layout.rows) * layout.cellSize.height
            bg.surfaceInset = size.height - gridTop + 5 * layout.cellSize.height
            bg.draw(background, in: CGRect(origin: .zero, size: size), ctx: ctx)
        }
        renderer.draw(engine.render(), layout: layout, in: ctx)
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to dir: URL, _ name: String) {
        let url = dir.appendingPathComponent("\(name).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
