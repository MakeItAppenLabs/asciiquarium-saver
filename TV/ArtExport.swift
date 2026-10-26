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
            iconLayers(size: CGSize(width: 400, height: 240), scale: scale, rows: 22, into: dir, name: "icon", suffix: suffix)
            write(topShelf(size: CGSize(width: 1920, height: 720), scale: scale), to: dir, "topshelf\(suffix)")
            write(topShelf(size: CGSize(width: 2320, height: 720), scale: scale), to: dir, "topshelf-wide\(suffix)")
        }
        iconLayers(size: CGSize(width: 1280, height: 768), scale: 1, rows: 22, into: dir, name: "appstore", suffix: "")
        exit(0)
    }

    /// Back: the sea and the water line. Middle: the castle and seaweed. Front: three fish.
    private static func iconLayers(size: CGSize, scale: Int, rows: Int, into dir: URL, name: String, suffix: String) {
        write(render(size: size, scale: scale, rows: rows, background: AquariumSettings.defaultGradient) { c in
            addEnvironment(c)
        }, to: dir, "\(name)-back\(suffix)")
        write(render(size: size, scale: scale, rows: rows, background: nil) { c in
            addCastle(c)
            addAllSeaweed(c)
        }, to: dir, "\(name)-middle\(suffix)")
        write(render(size: size, scale: scale, rows: rows, background: nil) { c in
            for _ in 0..<3 { addFish(c) }
            for _ in 0..<12 { c.engine.step() }
        }, to: dir, "\(name)-front\(suffix)")
    }

    /// A whole tank, seed 42, a few seconds in.
    private static func topShelf(size: CGSize, scale: Int) -> CGImage {
        render(size: size, scale: scale, rows: 24, background: AquariumSettings.defaultGradient) { c in
            addEnvironment(c)
            addCastle(c)
            addAllSeaweed(c)
            addAllFish(c)
            for _ in 0..<40 { c.engine.step() }
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
