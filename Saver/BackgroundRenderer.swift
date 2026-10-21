import CoreGraphics
import Foundation
import AquariumKit

/// Fills the view behind the grid: a solid color, or a vertical gradient from the water surface down.
///
/// The gradient is rendered once per size into a 16-bit-per-component bitmap with light dithering and
/// cached, so it has no banding and costs one image draw per frame.
final class BackgroundRenderer {
    /// Distance in points from the top of the drawn rect down to the water surface. The gradient's top
    /// color fills everything above it.
    var surfaceInset: CGFloat = 0

    private struct Key: Equatable {
        var top: RGB
        var bottom: RGB
        var pixelHeight: Int
        var surfacePixel: Int
    }

    /// Width of the cached gradient tile in pixels. A vertical gradient only varies by row, so a narrow
    /// tile repeated across the view keeps the memory small; the dither repeats too, invisibly.
    private static let tileWidth = 256
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private var cachedKey: Key?
    private var cachedTile: CGImage?

    func draw(_ bg: Background, in rect: CGRect, ctx: CGContext) {
        switch bg {
        case .solid(let color):
            ctx.setFillColor(Self.cgColor(color))
            ctx.fill(rect)
        case .gradient(let top, let bottom):
            drawGradient(top: top, bottom: bottom, in: rect, ctx: ctx)
        }
    }

    private func drawGradient(top: RGB, bottom: RGB, in rect: CGRect, ctx: CGContext) {
        let device = ctx.convertToDeviceSpace(rect).standardized
        let pixelHeight = Int(device.height.rounded())
        guard pixelHeight > 0, rect.height > 0, device.width > 0 else { return }
        let pixelsPerPoint = device.height / rect.height
        let surface = min(max(0, surfaceInset), rect.height)
        let key = Key(top: top, bottom: bottom, pixelHeight: pixelHeight,
                      surfacePixel: Int((surface * pixelsPerPoint).rounded()))

        if key != cachedKey || cachedTile == nil {
            cachedTile = Self.makeTile(key)
            cachedKey = key
        }
        guard let tile = cachedTile else {
            ctx.setFillColor(Self.cgColor(bottom))
            ctx.fill(rect)
            return
        }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.interpolationQuality = .none
        ctx.clip(to: rect)
        let tileWidth = CGFloat(Self.tileWidth) / (device.width / rect.width)
        var x = rect.minX
        while x < rect.maxX {
            ctx.draw(tile, in: CGRect(x: x, y: rect.minY, width: tileWidth, height: rect.height))
            x += tileWidth
        }
    }

    /// A `tileWidth` × `pixelHeight` RGBX bitmap, 16 bits per component, row 0 at the top. Each pixel
    /// gets triangular noise of about one 8-bit step, so the conversion to the display's depth dithers
    /// instead of banding.
    private static func makeTile(_ key: Key) -> CGImage? {
        let width = tileWidth
        let height = key.pixelHeight
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        var rng = SplitMix(state: 0x5EED_AC1D)
        let span = Double(max(1, height - key.surfacePixel))
        let top = [key.top.r, key.top.g, key.top.b]
        let bottom = [key.bottom.r, key.bottom.g, key.bottom.b]
        let noiseScale = 1.0 / 255.0

        for y in 0..<height {
            let t = min(max((Double(y) + 0.5 - Double(key.surfacePixel)) / span, 0), 1)
            let row = (0..<3).map { top[$0] + (bottom[$0] - top[$0]) * t }
            for x in 0..<width {
                let i = (y * width + x) * 4
                for c in 0..<3 {
                    let noise = (rng.nextUnit() + rng.nextUnit() - 1) * noiseScale
                    let v = min(max(row[c] + noise, 0), 1)
                    pixels[i + c] = UInt16((v * 65535).rounded())
                }
                pixels[i + 3] = 65535
            }
        }

        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: srgb,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                .union(.byteOrder16Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func cgColor(_ c: RGB) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// A tiny deterministic generator for the dither, so a redraw gives the same pixels.
    private struct SplitMix {
        var state: UInt64

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}
