import Foundation

/// An sRGB color with components in 0...1.
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB(r: 0, g: 0, b: 0)
}

/// Maps the eight ANSI colors, normal and bright, to RGB.
public struct Palette: Sendable {
    private let normal: [RGB]
    private let bright: [RGB]

    private init(normal: [RGB], bright: [RGB]) {
        self.normal = normal
        self.bright = bright
    }

    public func rgb(_ c: CellColor) -> RGB {
        let index = Int(c.color.rawValue)
        return c.bright ? bright[index] : normal[index]
    }

    private static func byte(_ r: Int, _ g: Int, _ b: Int) -> RGB {
        RGB(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }

    /// The macOS Terminal "Basic" profile colors, except blue, which is lifted (normal and bright) so
    /// it keeps a 3:1 contrast against both a black and the default gradient background.
    public static let terminal = Palette(
        normal: [
            byte(0, 0, 0),
            byte(153, 0, 0),
            byte(0, 166, 0),
            byte(153, 153, 0),
            RGB(r: 0.32, g: 0.32, b: 0.88),
            byte(178, 0, 178),
            byte(0, 166, 178),
            byte(191, 191, 191),
        ],
        bright: [
            byte(102, 102, 102),
            byte(230, 0, 0),
            byte(0, 217, 0),
            byte(230, 230, 0),
            RGB(r: 0.40, g: 0.40, b: 1.0),
            byte(230, 0, 230),
            byte(0, 230, 230),
            byte(230, 230, 230),
        ]
    )
}

/// WCAG 2.x contrast ratio (1...21) between two sRGB colors.
public func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    func linear(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    func luminance(_ c: RGB) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
    let la = luminance(a)
    let lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}
