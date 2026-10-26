import CoreText
import AquariumKit
#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

/// Draws a character grid as terminal text: SF Mono, regular for normal colors and bold for bright ones.
final class GridRenderer {
    /// One character cell: the advance of "M" by the line height, rounded up.
    let cellSize: CGSize

    private let regularFont: CTFont
    private let boldFont: CTFont
    /// Height of the baseline above the bottom of a cell, at this renderer's own cell height.
    private let baselineOffset: CGFloat
    private var attributes: [CellColor: [NSAttributedString.Key: Any]] = [:]
    private let palette: Palette

    /// Most runs (water line, castle, seaweed, fish) repeat from frame to frame, so their laid-out
    /// lines are kept. The cache is simply emptied when it grows past `lineCacheLimit`.
    private struct LineKey: Hashable {
        var text: String
        var color: CellColor
    }
    private var lineCache: [LineKey: CTLine] = [:]
    private static let lineCacheLimit = 4096

    init(pointSize: CGFloat, palette: Palette) {
        self.palette = palette
        let regular = PlatformFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let bold = PlatformFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)
        regularFont = regular as CTFont
        boldFont = bold as CTFont

        let lineHeight = regular.ascender - regular.descender + regular.leading
        let advance = Self.advance(of: UniChar(UInt8(ascii: "M")), in: regularFont)
        cellSize = CGSize(width: advance, height: ceil(lineHeight))
        // Split the spare height evenly above and below the glyphs.
        baselineOffset = -regular.descender + (cellSize.height - (regular.ascender - regular.descender)) / 2
    }

    /// Draws `grid` into the cells of `layout`, in an unflipped context (row 0 at the top).
    ///
    /// Each row's runs of same-colored, non-blank characters become one `CTLine`, started at its first
    /// cell with the origin snapped to a device pixel so the glyphs stay crisp.
    func draw(_ grid: Grid, layout: GridLayout, in ctx: CGContext) {
        let cell = layout.cellSize
        guard cell.width > 0, cell.height > 0 else { return }
        let cols = min(grid.cols, layout.cols)
        let rows = min(grid.rows, layout.rows)
        let baseline = baselineOffset * cell.height / cellSize.height

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.textMatrix = .identity

        var run = ""
        var runStart = 0
        var runColor: CellColor?

        for y in 0..<rows {
            let baselineY = layout.origin.y + CGFloat(layout.rows - 1 - y) * cell.height + baseline

            func flush() {
                if let color = runColor, !run.isEmpty {
                    let origin = CGPoint(x: layout.origin.x + CGFloat(runStart) * cell.width, y: baselineY)
                    drawRun(run, color: color, at: snapped(origin, in: ctx), in: ctx)
                }
                run = ""
                runColor = nil
            }

            for x in 0..<cols {
                guard let c = grid[x, y], c.char != " " else {
                    flush()
                    continue
                }
                if c.color != runColor {
                    flush()
                    runStart = x
                    runColor = c.color
                }
                run.append(c.char)
            }
            flush()
        }
    }

    private func drawRun(_ text: String, color: CellColor, at origin: CGPoint, in ctx: CGContext) {
        ctx.textPosition = origin
        CTLineDraw(line(for: LineKey(text: text, color: color)), ctx)
    }

    private func line(for key: LineKey) -> CTLine {
        if let cached = lineCache[key] { return cached }
        if lineCache.count >= Self.lineCacheLimit { lineCache.removeAll(keepingCapacity: true) }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: key.text, attributes: attributes(for: key.color)))
        lineCache[key] = line
        return line
    }

    private func attributes(for color: CellColor) -> [NSAttributedString.Key: Any] {
        if let cached = attributes[color] { return cached }
        let rgb = palette.rgb(color)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): color.bright ? boldFont : regularFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1),
            NSAttributedString.Key(kCTLigatureAttributeName as String): 0,
        ]
        attributes[color] = attrs
        return attrs
    }

    private func snapped(_ p: CGPoint, in ctx: CGContext) -> CGPoint {
        let d = ctx.convertToDeviceSpace(p)
        return ctx.convertToUserSpace(CGPoint(x: d.x.rounded(), y: d.y.rounded()))
    }

    private static func advance(of character: UniChar, in font: CTFont) -> CGFloat {
        var char = character
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &char, &glyph, 1) else {
            return CTFontGetSize(font) * 0.6
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }
}
